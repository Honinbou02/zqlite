//! Connection pooling for ZQLite

use crate::{Connection, Error, Result};
use std::collections::VecDeque;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};
use tracing::{debug, error, info, warn};

/// Configuration for a connection pool
#[derive(Debug, Clone)]
pub struct PoolConfig {
    /// Minimum number of connections to maintain
    pub min_connections: u32,
    /// Maximum number of connections to create
    pub max_connections: u32,
    /// Maximum time to wait for a connection
    pub connection_timeout: Duration,
    /// Maximum lifetime of a connection
    pub max_connection_lifetime: Duration,
    /// Maximum idle time for a connection
    pub max_idle_time: Duration,
    /// Test query to validate connections
    pub test_query: Option<String>,
}

impl Default for PoolConfig {
    fn default() -> Self {
        Self {
            min_connections: 1,
            max_connections: 10,
            connection_timeout: Duration::from_secs(30),
            max_connection_lifetime: Duration::from_secs(3600), // 1 hour
            max_idle_time: Duration::from_secs(600),           // 10 minutes
            test_query: Some("SELECT 1".to_string()),
        }
    }
}

/// Statistics about the connection pool
#[derive(Debug, Clone)]
pub struct PoolStats {
    /// Total connections created
    pub connections_created: u64,
    /// Total connections destroyed
    pub connections_destroyed: u64,
    /// Current active connections
    pub active_connections: u32,
    /// Current idle connections
    pub idle_connections: u32,
    /// Current waiting requests
    pub waiting_requests: u32,
}

struct PooledConnection {
    connection: Connection,
    created_at: Instant,
    last_used: Instant,
}

impl PooledConnection {
    fn new(connection: Connection) -> Self {
        let now = Instant::now();
        Self {
            connection,
            created_at: now,
            last_used: now,
        }
    }

    fn is_expired(&self, config: &PoolConfig) -> bool {
        let now = Instant::now();
        now.duration_since(self.created_at) > config.max_connection_lifetime
            || now.duration_since(self.last_used) > config.max_idle_time
    }

    fn touch(&mut self) {
        self.last_used = Instant::now();
    }

    fn is_valid(&self, config: &PoolConfig) -> bool {
        if let Some(ref test_query) = config.test_query {
            match self.connection.execute(test_query) {
                Ok(()) => true,
                Err(e) => {
                    debug!("Connection validation failed: {}", e);
                    false
                }
            }
        } else {
            true
        }
    }
}

struct PoolInner {
    config: PoolConfig,
    database_path: Option<String>,
    available: VecDeque<PooledConnection>,
    active_count: u32,
    stats: PoolStats,
    waiting: u32,
}

/// A connection pool for ZQLite connections
pub struct ConnectionPool {
    inner: Arc<Mutex<PoolInner>>,
    condvar: Arc<Condvar>,
}

impl ConnectionPool {
    /// Create a new connection pool
    pub fn new(database_path: Option<&str>, config: PoolConfig) -> Result<Self> {
        let inner = PoolInner {
            config,
            database_path: database_path.map(|s| s.to_string()),
            available: VecDeque::new(),
            active_count: 0,
            stats: PoolStats {
                connections_created: 0,
                connections_destroyed: 0,
                active_connections: 0,
                idle_connections: 0,
                waiting_requests: 0,
            },
            waiting: 0,
        };

        let pool = Self {
            inner: Arc::new(Mutex::new(inner)),
            condvar: Arc::new(Condvar::new()),
        };

        // Create initial connections
        pool.initialize_connections()?;

        info!(
            "Created connection pool with {}-{} connections",
            pool.inner.lock().unwrap().config.min_connections,
            pool.inner.lock().unwrap().config.max_connections
        );

        Ok(pool)
    }

    /// Create a new connection pool with default configuration
    pub fn new_default(database_path: Option<&str>) -> Result<Self> {
        Self::new(database_path, PoolConfig::default())
    }

    /// Initialize the minimum number of connections
    fn initialize_connections(&self) -> Result<()> {
        let mut inner = self.inner.lock().unwrap();
        let min_connections = inner.config.min_connections;

        for _ in 0..min_connections {
            let conn = self.create_connection(&inner.database_path)?;
            let pooled_conn = PooledConnection::new(conn);
            inner.available.push_back(pooled_conn);
            inner.stats.connections_created += 1;
        }

        inner.stats.idle_connections = min_connections;
        Ok(())
    }

    /// Create a new database connection
    fn create_connection(&self, database_path: &Option<String>) -> Result<Connection> {
        match database_path {
            Some(path) => Connection::open(path),
            None => Connection::open(":memory:"),
        }
    }

    /// Get a connection from the pool
    pub fn get_connection(&self) -> Result<PooledConnectionGuard> {
        let start = Instant::now();
        let timeout = {
            let inner = self.inner.lock().unwrap();
            inner.config.connection_timeout
        };

        loop {
            let mut inner = self.inner.lock().unwrap();

            // Check for available connections
            while let Some(mut pooled_conn) = inner.available.pop_front() {
                inner.stats.idle_connections = inner.stats.idle_connections.saturating_sub(1);

                // Check if connection is still valid
                if pooled_conn.is_expired(&inner.config) || !pooled_conn.is_valid(&inner.config) {
                    debug!("Discarding expired or invalid connection");
                    inner.stats.connections_destroyed += 1;
                    continue;
                }

                pooled_conn.touch();
                inner.active_count += 1;
                inner.stats.active_connections += 1;

                debug!("Acquired connection from pool");
                return Ok(PooledConnectionGuard {
                    connection: Some(pooled_conn.connection),
                    pool: Arc::clone(&self.inner),
                    condvar: Arc::clone(&self.condvar),
                });
            }

            // No available connections, try to create a new one
            if inner.active_count + inner.available.len() as u32 < inner.config.max_connections {
                match self.create_connection(&inner.database_path) {
                    Ok(conn) => {
                        inner.active_count += 1;
                        inner.stats.connections_created += 1;
                        inner.stats.active_connections += 1;

                        debug!("Created new connection");
                        return Ok(PooledConnectionGuard {
                            connection: Some(conn),
                            pool: Arc::clone(&self.inner),
                            condvar: Arc::clone(&self.condvar),
                        });
                    }
                    Err(e) => {
                        error!("Failed to create new connection: {}", e);
                        return Err(e);
                    }
                }
            }

            // Pool is full, wait for a connection to be returned
            if start.elapsed() >= timeout {
                return Err(Error::pool_error("Connection timeout"));
            }

            inner.waiting += 1;
            inner.stats.waiting_requests += 1;
            warn!("Pool exhausted, waiting for available connection");

            let result = self.condvar.wait_timeout(inner, timeout - start.elapsed());
            inner = result.0;
            inner.waiting -= 1;

            if result.1.timed_out() {
                return Err(Error::pool_error("Connection timeout"));
            }
        }
    }

    /// Get current pool statistics
    pub fn stats(&self) -> PoolStats {
        let inner = self.inner.lock().unwrap();
        inner.stats.clone()
    }

    /// Get the current pool configuration
    pub fn config(&self) -> PoolConfig {
        let inner = self.inner.lock().unwrap();
        inner.config.clone()
    }

    /// Perform maintenance on the pool (remove expired connections)
    pub fn maintain(&self) {
        let mut inner = self.inner.lock().unwrap();
        let mut to_remove = Vec::new();

        for (index, conn) in inner.available.iter().enumerate() {
            if conn.is_expired(&inner.config) {
                to_remove.push(index);
            }
        }

        // Remove expired connections (in reverse order to maintain indices)
        for &index in to_remove.iter().rev() {
            inner.available.remove(index);
            inner.stats.connections_destroyed += 1;
            inner.stats.idle_connections = inner.stats.idle_connections.saturating_sub(1);
        }

        if !to_remove.is_empty() {
            debug!("Removed {} expired connections", to_remove.len());
        }

        // Ensure minimum connections
        let current_total = inner.active_count + inner.available.len() as u32;
        if current_total < inner.config.min_connections {
            let to_create = inner.config.min_connections - current_total;
            for _ in 0..to_create {
                if let Ok(conn) = self.create_connection(&inner.database_path) {
                    let pooled_conn = PooledConnection::new(conn);
                    inner.available.push_back(pooled_conn);
                    inner.stats.connections_created += 1;
                    inner.stats.idle_connections += 1;
                }
            }
        }
    }

    /// Close the pool and all connections
    pub fn close(&self) {
        let mut inner = self.inner.lock().unwrap();
        inner.available.clear();
        inner.stats.connections_destroyed += inner.stats.idle_connections as u64;
        inner.stats.idle_connections = 0;
        info!("Connection pool closed");
    }
}

/// A connection guard that automatically returns the connection to the pool
pub struct PooledConnectionGuard {
    connection: Option<Connection>,
    pool: Arc<Mutex<PoolInner>>,
    condvar: Arc<Condvar>,
}

impl std::ops::Deref for PooledConnectionGuard {
    type Target = Connection;

    fn deref(&self) -> &Self::Target {
        self.connection.as_ref().unwrap()
    }
}

impl Drop for PooledConnectionGuard {
    fn drop(&mut self) {
        if let Some(connection) = self.connection.take() {
            let mut inner = self.pool.lock().unwrap();

            // Check if we should keep this connection
            let should_keep = inner.available.len() < inner.config.max_connections as usize
                && inner.active_count + inner.available.len() as u32 >= inner.config.min_connections;

            if should_keep {
                let pooled_conn = PooledConnection::new(connection);
                inner.available.push_back(pooled_conn);
                inner.stats.idle_connections += 1;
                debug!("Returned connection to pool");
            } else {
                inner.stats.connections_destroyed += 1;
                debug!("Discarded excess connection");
            }

            inner.active_count = inner.active_count.saturating_sub(1);
            inner.stats.active_connections = inner.stats.active_connections.saturating_sub(1);

            // Notify waiting threads
            if inner.waiting > 0 {
                self.condvar.notify_one();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;

    #[test]
    fn test_pool_creation() {
        let pool = ConnectionPool::new_default(None).unwrap();
        let stats = pool.stats();

        assert_eq!(stats.connections_created, 1); // Default min_connections
        assert_eq!(stats.idle_connections, 1);
        assert_eq!(stats.active_connections, 0);
    }

    #[test]
    fn test_get_and_return_connection() {
        let pool = ConnectionPool::new_default(None).unwrap();

        {
            let conn = pool.get_connection().unwrap();
            conn.execute("CREATE TABLE test (id INTEGER)").unwrap();

            let stats = pool.stats();
            assert_eq!(stats.active_connections, 1);
            assert_eq!(stats.idle_connections, 0);
        } // Connection should be returned here

        let stats = pool.stats();
        assert_eq!(stats.active_connections, 0);
        assert_eq!(stats.idle_connections, 1);
    }

    #[test]
    fn test_concurrent_access() {
        let pool = Arc::new(
            ConnectionPool::new(
                None,
                PoolConfig {
                    min_connections: 2,
                    max_connections: 4,
                    ..Default::default()
                },
            )
            .unwrap(),
        );

        let mut handles = vec![];

        for i in 0..8 {
            let pool_clone = Arc::clone(&pool);
            let handle = thread::spawn(move || {
                let conn = pool_clone.get_connection().unwrap();
                conn.execute(&format!("CREATE TABLE IF NOT EXISTS test{} (id INTEGER)", i))
                    .unwrap();
                thread::sleep(Duration::from_millis(100));
            });
            handles.push(handle);
        }

        for handle in handles {
            handle.join().unwrap();
        }

        let stats = pool.stats();
        assert!(stats.connections_created >= 2);
        assert!(stats.connections_created <= 4);
    }

    #[test]
    fn test_pool_maintenance() {
        let config = PoolConfig {
            min_connections: 1,
            max_connections: 3,
            max_idle_time: Duration::from_millis(100),
            ..Default::default()
        };

        let pool = ConnectionPool::new(None, config).unwrap();

        // Create some connections
        let _conn1 = pool.get_connection().unwrap();
        let _conn2 = pool.get_connection().unwrap();

        drop(_conn1);
        drop(_conn2);

        // Wait for connections to become idle
        thread::sleep(Duration::from_millis(150));

        let stats_before = pool.stats();
        pool.maintain();
        let stats_after = pool.stats();

        assert!(stats_after.connections_destroyed >= stats_before.connections_destroyed);
        assert_eq!(stats_after.idle_connections, 1); // Should maintain min_connections
    }
}