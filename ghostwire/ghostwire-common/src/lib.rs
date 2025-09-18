//! Common types and utilities for Ghostwire mesh VPN

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use uuid::Uuid;

pub mod crypto;
pub mod network;
pub mod protocol;

/// Peer information in the mesh network
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PeerInfo {
    /// Unique peer identifier
    pub id: Uuid,
    /// WireGuard public key
    pub public_key: PublicKey,
    /// Available endpoints for this peer
    pub endpoints: Vec<SocketAddr>,
    /// Last seen timestamp
    pub last_seen: chrono::DateTime<chrono::Utc>,
    /// Peer metadata
    pub metadata: PeerMetadata,
    /// Network access control list
    pub acl_rules: Vec<AclRule>,
}

/// WireGuard public key wrapper
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PublicKey(pub [u8; 32]);

impl PublicKey {
    /// Create from base64 string
    pub fn from_base64(s: &str) -> Result<Self, base64::DecodeError> {
        let bytes = base64::decode(s)?;
        if bytes.len() != 32 {
            return Err(base64::DecodeError::InvalidLength);
        }
        let mut key = [0u8; 32];
        key.copy_from_slice(&bytes);
        Ok(PublicKey(key))
    }

    /// Convert to base64 string
    pub fn to_base64(&self) -> String {
        base64::encode(self.0)
    }
}

/// Peer metadata
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct PeerMetadata {
    /// Peer name/hostname
    pub name: Option<String>,
    /// Operating system
    pub os: Option<String>,
    /// Client version
    pub version: Option<String>,
    /// Tags for organization
    pub tags: HashMap<String, String>,
    /// Custom attributes
    pub attributes: serde_json::Value,
}

/// Access Control List rule
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AclRule {
    /// Rule identifier
    pub id: Uuid,
    /// Source CIDR block
    pub source_cidr: String,
    /// Destination CIDR block
    pub dest_cidr: String,
    /// Action to take
    pub action: AclAction,
    /// Rule priority (higher values take precedence)
    pub priority: i32,
    /// Optional description
    pub description: Option<String>,
}

/// ACL action
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum AclAction {
    Allow,
    Deny,
}

/// Network route information
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Route {
    /// Network identifier
    pub network_id: Uuid,
    /// CIDR block for this route
    pub cidr: String,
    /// Peer responsible for this route
    pub peer_id: Uuid,
    /// Route metric (lower values preferred)
    pub metric: u32,
    /// Route advertisement source
    pub advertised_by: Uuid,
    /// Timestamp when route was advertised
    pub advertised_at: chrono::DateTime<chrono::Utc>,
}

/// Network topology information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkTopology {
    /// All peers in the network
    pub peers: HashMap<Uuid, PeerInfo>,
    /// Available routes
    pub routes: Vec<Route>,
    /// Network-wide ACL rules
    pub global_acl: Vec<AclRule>,
    /// Topology generation/version
    pub generation: u64,
    /// Last updated timestamp
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

/// Peer registration request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterPeerRequest {
    /// Peer public key
    pub public_key: PublicKey,
    /// Available endpoints
    pub endpoints: Vec<SocketAddr>,
    /// Peer metadata
    pub metadata: PeerMetadata,
}

/// Peer registration response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterPeerResponse {
    /// Assigned peer ID
    pub peer_id: Uuid,
    /// Assigned IP address
    pub assigned_ip: IpAddr,
    /// Network configuration
    pub network_config: NetworkConfig,
    /// Initial ACL rules for this peer
    pub acl_rules: Vec<AclRule>,
}

/// Network configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkConfig {
    /// Network CIDR block
    pub network_cidr: String,
    /// DNS servers
    pub dns_servers: Vec<IpAddr>,
    /// Search domains
    pub search_domains: Vec<String>,
    /// MTU setting
    pub mtu: u16,
    /// Keep-alive interval
    pub keep_alive: Option<std::time::Duration>,
}

/// Health check information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthCheck {
    /// Peer ID
    pub peer_id: Uuid,
    /// Timestamp
    pub timestamp: chrono::DateTime<chrono::Utc>,
    /// Latency to coordination server
    pub server_latency_ms: Option<f64>,
    /// Connected peer count
    pub connected_peers: u32,
    /// Bytes received
    pub rx_bytes: u64,
    /// Bytes transmitted
    pub tx_bytes: u64,
}

/// Coordination server configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    /// Server bind address
    pub bind_address: SocketAddr,
    /// Database path
    pub database_path: String,
    /// Network CIDR for IP allocation
    pub network_cidr: String,
    /// TLS certificate path
    pub tls_cert_path: Option<String>,
    /// TLS private key path
    pub tls_key_path: Option<String>,
    /// Metrics server configuration
    pub metrics_config: MetricsConfig,
    /// Log level
    pub log_level: String,
}

/// Metrics configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsConfig {
    /// Enable metrics collection
    pub enabled: bool,
    /// Prometheus metrics server address
    pub prometheus_address: Option<SocketAddr>,
    /// Metrics endpoint path
    pub metrics_path: String,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            bind_address: "0.0.0.0:8080".parse().unwrap(),
            database_path: "ghostwire.db".to_string(),
            network_cidr: "10.0.0.0/8".to_string(),
            tls_cert_path: None,
            tls_key_path: None,
            metrics_config: MetricsConfig {
                enabled: true,
                prometheus_address: Some("0.0.0.0:9090".parse().unwrap()),
                metrics_path: "/metrics".to_string(),
            },
            log_level: "info".to_string(),
        }
    }
}

/// Error types for Ghostwire operations
#[derive(Debug, thiserror::Error)]
pub enum GhostwireError {
    /// Database operation failed
    #[error("Database error: {0}")]
    Database(#[from] anyhow::Error),

    /// Network operation failed
    #[error("Network error: {0}")]
    Network(String),

    /// Invalid configuration
    #[error("Configuration error: {0}")]
    Config(String),

    /// Peer not found
    #[error("Peer not found: {0}")]
    PeerNotFound(Uuid),

    /// Invalid CIDR block
    #[error("Invalid CIDR: {0}")]
    InvalidCidr(String),

    /// ACL evaluation error
    #[error("ACL error: {0}")]
    Acl(String),

    /// Cryptographic operation failed
    #[error("Crypto error: {0}")]
    Crypto(String),

    /// Serialization/deserialization error
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
}

/// Result type for Ghostwire operations
pub type Result<T> = std::result::Result<T, GhostwireError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_public_key_encoding() {
        let key_bytes = [1u8; 32];
        let public_key = PublicKey(key_bytes);

        let base64_str = public_key.to_base64();
        let decoded = PublicKey::from_base64(&base64_str).unwrap();

        assert_eq!(public_key, decoded);
    }

    #[test]
    fn test_peer_info_serialization() {
        let peer = PeerInfo {
            id: Uuid::new_v4(),
            public_key: PublicKey([1u8; 32]),
            endpoints: vec!["192.168.1.1:51820".parse().unwrap()],
            last_seen: chrono::Utc::now(),
            metadata: PeerMetadata::default(),
            acl_rules: vec![],
        };

        let json = serde_json::to_string(&peer).unwrap();
        let deserialized: PeerInfo = serde_json::from_str(&json).unwrap();

        assert_eq!(peer, deserialized);
    }

    #[test]
    fn test_default_server_config() {
        let config = ServerConfig::default();
        assert!(config.metrics_config.enabled);
        assert_eq!(config.log_level, "info");
        assert_eq!(config.network_cidr, "10.0.0.0/8");
    }
}