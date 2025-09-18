//! Coordination server implementation with ZQLite backend

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use ghostwire_common::{
    network::IpAllocator, AclAction, AclRule, GhostwireError, NetworkTopology, PeerInfo,
    PublicKey, RegisterPeerRequest, RegisterPeerResponse, Route, ServerConfig
};
use std::{collections::HashMap, net::IpAddr, sync::Arc};
use tokio::sync::RwLock;
use tracing::{debug, error, info, instrument, warn};
use uuid::Uuid;
use zqlite_rs::{AsyncConnectionPool, PoolConfig, ZQLiteMetrics};

/// Coordination server managing the mesh VPN network
pub struct CoordinationServer {
    database: Arc<AsyncConnectionPool>,
    ip_allocator: Arc<RwLock<IpAllocator>>,
    metrics: ZQLiteMetrics,
    config: ServerConfig,
}

impl CoordinationServer {
    /// Create a new coordination server
    #[instrument(skip(config, metrics))]
    pub async fn new(config: &ServerConfig, metrics: ZQLiteMetrics) -> Result<Self> {
        info!("Initializing coordination server with ZQLite backend");

        // Create database connection pool
        let pool_config = PoolConfig {
            min_connections: 2,
            max_connections: 10,
            connection_timeout: std::time::Duration::from_secs(30),
            ..Default::default()
        };

        let database = AsyncConnectionPool::new(Some(&config.database_path), pool_config)
            .await
            .context("Failed to create database connection pool")?;

        info!("Database connection pool created: {}", config.database_path);

        // Initialize database schema
        let conn = database.get_connection().await?;
        Self::initialize_schema(&conn).await?;

        // Create IP allocator
        let ip_allocator = Arc::new(RwLock::new(
            IpAllocator::new(&config.network_cidr)
                .context("Failed to create IP allocator")?,
        ));

        info!("IP allocator initialized for network: {}", config.network_cidr);

        Ok(Self {
            database: Arc::new(database),
            ip_allocator,
            metrics,
            config: config.clone(),
        })
    }

    /// Initialize the database schema
    #[instrument(skip(conn))]
    async fn initialize_schema(conn: &zqlite_rs::AsyncConnection) -> Result<()> {
        info!("Initializing database schema");

        // Peers table with ZQLite optimizations
        conn.execute(
            "CREATE TABLE IF NOT EXISTS peers (
                id TEXT PRIMARY KEY,
                public_key BLOB NOT NULL UNIQUE,
                assigned_ip TEXT NOT NULL UNIQUE,
                endpoints TEXT COMPRESSED,  -- ZQLite compression for JSON
                last_seen REAL NOT NULL,
                metadata TEXT COMPRESSED,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                INDEX idx_peers_last_seen(last_seen),  -- ZQLite fast index
                INDEX idx_peers_assigned_ip(assigned_ip)
            )"
        ).await.context("Failed to create peers table")?;

        // ACL rules with bitmap indexing
        conn.execute(
            "CREATE TABLE IF NOT EXISTS acl_rules (
                id TEXT PRIMARY KEY,
                peer_id TEXT,
                source_cidr TEXT NOT NULL,
                dest_cidr TEXT NOT NULL,
                action TEXT NOT NULL CHECK(action IN ('allow', 'deny')),
                priority INTEGER NOT NULL DEFAULT 0,
                description TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                INDEX idx_acl_priority(priority) USING BITMAP,  -- ZQLite bitmap index
                INDEX idx_acl_peer_id(peer_id),
                FOREIGN KEY (peer_id) REFERENCES peers(id) ON DELETE CASCADE
            )"
        ).await.context("Failed to create acl_rules table")?;

        // Network routes with spatial indexing
        conn.execute(
            "CREATE TABLE IF NOT EXISTS routes (
                network_id TEXT PRIMARY KEY,
                cidr TEXT NOT NULL,
                peer_id TEXT NOT NULL,
                metric INTEGER DEFAULT 100,
                advertised_by TEXT NOT NULL,
                advertised_at REAL NOT NULL,
                created_at REAL NOT NULL,
                INDEX idx_routes_cidr(cidr) USING RTREE,  -- ZQLite R-tree for CIDR
                INDEX idx_routes_peer_id(peer_id),
                FOREIGN KEY (peer_id) REFERENCES peers(id) ON DELETE CASCADE,
                FOREIGN KEY (advertised_by) REFERENCES peers(id) ON DELETE CASCADE
            )"
        ).await.context("Failed to create routes table")?;

        // Health metrics with time-series optimization
        conn.execute(
            "CREATE TABLE IF NOT EXISTS health_metrics (
                peer_id TEXT NOT NULL,
                timestamp REAL NOT NULL,
                server_latency_ms REAL,
                connected_peers INTEGER,
                rx_bytes INTEGER,
                tx_bytes INTEGER,
                PRIMARY KEY (peer_id, timestamp),
                FOREIGN KEY (peer_id) REFERENCES peers(id) ON DELETE CASCADE
            ) WITH TIME_SERIES(interval='1m', retention='7d')"  // ZQLite time-series
        ).await.context("Failed to create health_metrics table")?;

        info!("Database schema initialized successfully");
        Ok(())
    }

    /// Register a new peer in the network
    #[instrument(skip(self, request), fields(public_key = %request.public_key.to_base64()))]
    pub async fn register_peer(&self, request: RegisterPeerRequest) -> Result<RegisterPeerResponse, GhostwireError> {
        let start_time = std::time::Instant::now();

        info!("Registering new peer");

        // Allocate IP address
        let assigned_ip = {
            let mut allocator = self.ip_allocator.write().await;
            allocator.allocate()
                .map_err(|e| GhostwireError::Network(format!("IP allocation failed: {}", e)))?
        };

        let peer_id = Uuid::new_v4();
        let now = Utc::now().timestamp() as f64;

        // Store peer in database
        let conn = self.database.get_connection().await
            .map_err(|e| GhostwireError::Database(e.into()))?;

        let endpoints_json = serde_json::to_string(&request.endpoints)
            .map_err(|e| GhostwireError::Serialization(e))?;
        let metadata_json = serde_json::to_string(&request.metadata)
            .map_err(|e| GhostwireError::Serialization(e))?;

        conn.execute(&format!(
            "INSERT INTO peers (id, public_key, assigned_ip, endpoints, last_seen, metadata, created_at, updated_at)
             VALUES ('{}', X'{}', '{}', '{}', {}, '{}', {}, {})",
            peer_id,
            hex::encode(&request.public_key.0),
            assigned_ip,
            endpoints_json,
            now,
            metadata_json,
            now,
            now
        )).await.map_err(|e| GhostwireError::Database(e.into()))?;

        // Get default ACL rules for the peer
        let acl_rules = self.get_default_acl_rules().await?;

        let response = RegisterPeerResponse {
            peer_id,
            assigned_ip: IpAddr::V4(assigned_ip),
            network_config: self.get_network_config(),
            acl_rules,
        };

        let duration = start_time.elapsed();
        self.metrics.query_executed("INSERT INTO peers", duration, true);

        info!(
            peer_id = %peer_id,
            assigned_ip = %assigned_ip,
            duration_ms = duration.as_millis(),
            "Peer registered successfully"
        );

        Ok(response)
    }

    /// Get peer information by ID
    #[instrument(skip(self))]
    pub async fn get_peer(&self, peer_id: Uuid) -> Result<PeerInfo, GhostwireError> {
        let start_time = std::time::Instant::now();

        let conn = self.database.get_connection().await
            .map_err(|e| GhostwireError::Database(e.into()))?;

        let rows = conn.query(&format!(
            "SELECT id, public_key, assigned_ip, endpoints, last_seen, metadata, created_at, updated_at
             FROM peers WHERE id = '{}'",
            peer_id
        )).await.map_err(|e| GhostwireError::Database(e.into()))?;

        if rows.row_count() == 0 {
            return Err(GhostwireError::PeerNotFound(peer_id));
        }

        let peer_info = self.row_to_peer_info(rows.into_iter().next().unwrap()).await?;

        let duration = start_time.elapsed();
        self.metrics.query_executed("SELECT FROM peers", duration, true);

        debug!(peer_id = %peer_id, "Retrieved peer information");
        Ok(peer_info)
    }

    /// List all peers with pagination
    #[instrument(skip(self))]
    pub async fn list_peers(&self, offset: u32, limit: u32) -> Result<Vec<PeerInfo>, GhostwireError> {
        let start_time = std::time::Instant::now();

        let conn = self.database.get_connection().await
            .map_err(|e| GhostwireError::Database(e.into()))?;

        let rows = conn.query(&format!(
            "SELECT id, public_key, assigned_ip, endpoints, last_seen, metadata, created_at, updated_at
             FROM peers
             ORDER BY created_at DESC
             LIMIT {} OFFSET {}",
            limit, offset
        )).await.map_err(|e| GhostwireError::Database(e.into()))?;

        let mut peers = Vec::with_capacity(rows.row_count());
        for row in rows {
            peers.push(self.row_to_peer_info(row).await?);
        }

        let duration = start_time.elapsed();
        self.metrics.query_executed("SELECT FROM peers (list)", duration, true);
        self.metrics.query_rows_returned(peers.len());

        debug!(count = peers.len(), "Retrieved peer list");
        Ok(peers)
    }

    /// Update peer health information
    #[instrument(skip(self))]
    pub async fn update_peer_health(&self, health: &ghostwire_common::HealthCheck) -> Result<(), GhostwireError> {
        let conn = self.database.get_connection().await
            .map_err(|e| GhostwireError::Database(e.into()))?;

        let timestamp = health.timestamp.timestamp() as f64;

        // Update last_seen in peers table
        conn.execute(&format!(
            "UPDATE peers SET last_seen = {} WHERE id = '{}'",
            timestamp, health.peer_id
        )).await.map_err(|e| GhostwireError::Database(e.into()))?;

        // Insert health metrics
        conn.execute(&format!(
            "INSERT INTO health_metrics (peer_id, timestamp, server_latency_ms, connected_peers, rx_bytes, tx_bytes)
             VALUES ('{}', {}, {}, {}, {}, {})",
            health.peer_id,
            timestamp,
            health.server_latency_ms.map_or("NULL".to_string(), |v| v.to_string()),
            health.connected_peers,
            health.rx_bytes,
            health.tx_bytes
        )).await.map_err(|e| GhostwireError::Database(e.into()))?;

        debug!(peer_id = %health.peer_id, "Updated peer health");
        Ok(())
    }

    /// Get network topology
    #[instrument(skip(self))]
    pub async fn get_topology(&self) -> Result<NetworkTopology, GhostwireError> {
        let start_time = std::time::Instant::now();

        // Get all peers
        let peers_list = self.list_peers(0, 1000).await?; // TODO: Handle large networks better
        let mut peers = HashMap::new();
        for peer in peers_list {
            peers.insert(peer.id, peer);
        }

        // Get routes
        let routes = self.get_all_routes().await?;

        // Get global ACL rules
        let global_acl = self.get_global_acl_rules().await?;

        let topology = NetworkTopology {
            peers,
            routes,
            global_acl,
            generation: self.get_topology_generation().await?,
            updated_at: Utc::now(),
        };

        let duration = start_time.elapsed();
        self.metrics.query_executed("get_topology", duration, true);

        info!(
            peers_count = topology.peers.len(),
            routes_count = topology.routes.len(),
            "Retrieved network topology"
        );

        Ok(topology)
    }

    /// Evaluate ACL for a connection between two peers
    #[instrument(skip(self))]
    pub async fn evaluate_acl(&self, source_ip: &str, dest_ip: &str) -> Result<bool, GhostwireError> {
        let start_time = std::time::Instant::now();

        let conn = self.database.get_connection().await
            .map_err(|e| GhostwireError::Database(e.into()))?;

        // Use ZQLite's subnet matching operators for fast ACL evaluation
        let rows = conn.query(&format!(
            "SELECT action
             FROM acl_rules
             WHERE '{}' <<= source_cidr  -- ZQLite subnet match operator
               AND '{}' <<= dest_cidr
             ORDER BY priority DESC
             LIMIT 1",
            source_ip, dest_ip
        )).await.map_err(|e| GhostwireError::Database(e.into()))?;

        let allowed = if rows.row_count() > 0 {
            let row = rows.into_iter().next().unwrap();
            let action: String = row.get(0).map_err(|e| GhostwireError::Database(e.into()))?;
            action == "allow"
        } else {
            false // Default deny
        };

        let duration = start_time.elapsed();
        self.metrics.query_executed("ACL evaluation", duration, true);

        debug!(
            source_ip = source_ip,
            dest_ip = dest_ip,
            allowed = allowed,
            "ACL evaluation completed"
        );

        Ok(allowed)
    }

    /// Helper method to convert database row to PeerInfo
    async fn row_to_peer_info(&self, row: zqlite_rs::Row) -> Result<PeerInfo, GhostwireError> {
        let id: String = row.get(0).map_err(|e| GhostwireError::Database(e.into()))?;
        let public_key_hex: String = row.get(1).map_err(|e| GhostwireError::Database(e.into()))?;
        let endpoints_json: String = row.get(3).map_err(|e| GhostwireError::Database(e.into()))?;
        let last_seen_timestamp: f64 = row.get(4).map_err(|e| GhostwireError::Database(e.into()))?;
        let metadata_json: String = row.get(5).map_err(|e| GhostwireError::Database(e.into()))?;

        let peer_id = Uuid::parse_str(&id)
            .map_err(|_| GhostwireError::Database("Invalid peer ID".into()))?;

        let public_key_bytes = hex::decode(public_key_hex)
            .map_err(|_| GhostwireError::Database("Invalid public key".into()))?;
        let mut public_key_array = [0u8; 32];
        public_key_array.copy_from_slice(&public_key_bytes);
        let public_key = PublicKey(public_key_array);

        let endpoints = serde_json::from_str(&endpoints_json)
            .map_err(|e| GhostwireError::Serialization(e))?;

        let metadata = serde_json::from_str(&metadata_json)
            .map_err(|e| GhostwireError::Serialization(e))?;

        let last_seen = DateTime::from_timestamp(last_seen_timestamp as i64, 0)
            .unwrap_or_else(|| Utc::now());

        // Get ACL rules for this peer
        let acl_rules = self.get_peer_acl_rules(peer_id).await?;

        Ok(PeerInfo {
            id: peer_id,
            public_key,
            endpoints,
            last_seen,
            metadata,
            acl_rules,
        })
    }

    /// Get default ACL rules for new peers
    async fn get_default_acl_rules(&self) -> Result<Vec<AclRule>, GhostwireError> {
        // Return basic allow-all rule for the network
        Ok(vec![AclRule {
            id: Uuid::new_v4(),
            source_cidr: self.config.network_cidr.clone(),
            dest_cidr: self.config.network_cidr.clone(),
            action: AclAction::Allow,
            priority: 0,
            description: Some("Default allow rule for network".to_string()),
        }])
    }

    /// Get network configuration
    fn get_network_config(&self) -> ghostwire_common::NetworkConfig {
        ghostwire_common::NetworkConfig {
            network_cidr: self.config.network_cidr.clone(),
            dns_servers: vec!["1.1.1.1".parse().unwrap(), "8.8.8.8".parse().unwrap()],
            search_domains: vec![],
            mtu: 1420,
            keep_alive: Some(std::time::Duration::from_secs(25)),
        }
    }

    /// Get ACL rules for a specific peer
    async fn get_peer_acl_rules(&self, peer_id: Uuid) -> Result<Vec<AclRule>, GhostwireError> {
        // Simplified implementation - in practice, you'd query the database
        Ok(vec![])
    }

    /// Get all routes in the network
    async fn get_all_routes(&self) -> Result<Vec<Route>, GhostwireError> {
        // Simplified implementation
        Ok(vec![])
    }

    /// Get global ACL rules
    async fn get_global_acl_rules(&self) -> Result<Vec<AclRule>, GhostwireError> {
        // Simplified implementation
        Ok(vec![])
    }

    /// Get current topology generation/version
    async fn get_topology_generation(&self) -> Result<u64, GhostwireError> {
        // Simplified implementation
        Ok(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ghostwire_common::{PeerMetadata, ServerConfig};
    use std::net::SocketAddr;
    use tempfile::NamedTempFile;

    async fn create_test_server() -> CoordinationServer {
        let temp_file = NamedTempFile::new().unwrap();
        let config = ServerConfig {
            database_path: temp_file.path().to_string_lossy().to_string(),
            network_cidr: "10.0.0.0/24".to_string(),
            ..Default::default()
        };

        let metrics = ZQLiteMetrics::new("test");
        CoordinationServer::new(&config, metrics).await.unwrap()
    }

    #[tokio::test]
    async fn test_peer_registration() {
        let server = create_test_server().await;

        let request = RegisterPeerRequest {
            public_key: PublicKey([1u8; 32]),
            endpoints: vec!["192.168.1.100:51820".parse().unwrap()],
            metadata: PeerMetadata::default(),
        };

        let response = server.register_peer(request).await.unwrap();

        assert!(response.peer_id != Uuid::nil());
        assert!(response.assigned_ip.to_string().starts_with("10.0.0."));

        // Verify peer can be retrieved
        let peer_info = server.get_peer(response.peer_id).await.unwrap();
        assert_eq!(peer_info.id, response.peer_id);
    }

    #[tokio::test]
    async fn test_acl_evaluation() {
        let server = create_test_server().await;

        // Test default deny behavior
        let allowed = server.evaluate_acl("10.0.0.100", "10.0.0.200").await.unwrap();
        assert!(!allowed); // Should be denied by default
    }
}