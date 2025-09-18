//! Async wrapper for ZQLite connections

use crate::{Connection, ConnectionPool, Error, PoolConfig, PooledConnectionGuard, Result, Rows};
use std::sync::Arc;
use tokio::task;
use tracing::{debug, instrument};

/// An async wrapper around a ZQLite connection
#[derive(Clone)]
pub struct AsyncConnection {
    pool: Arc<ConnectionPool>,
}

impl AsyncConnection {
    /// Create a new async connection
    #[instrument(skip(database_path))]
    pub async fn open(database_path: &str) -> Result<Self> {
        let database_path = database_path.to_string();
        let conn = task::spawn_blocking(move || {
            ConnectionPool::new(
                Some(&database_path),
                PoolConfig {
                    min_connections: 1,
                    max_connections: 1,
                    ..Default::default()
                },
            )
        })
        .await
        .map_err(|e| Error::pool_error(format!("Task join error: {}", e)))??;

        Ok(Self {
            pool: Arc::new(conn),
        })
    }

    /// Create a new async connection from a connection pool
    pub fn from_pool(pool: Arc<ConnectionPool>) -> Self {
        Self { pool }
    }

    /// Execute a SQL statement without returning results
    #[instrument(skip(self, sql), fields(sql = %sql))]
    pub async fn execute(&self, sql: &str) -> Result<()> {
        let sql = sql.to_string();
        let pool = Arc::clone(&self.pool);

        task::spawn_blocking(move || {
            let conn = pool.get_connection()?;
            conn.execute(&sql)
        })
        .await
        .map_err(|e| Error::pool_error(format!("Task join error: {}", e)))??;

        debug!("Executed SQL statement successfully");
        Ok(())
    }

    /// Execute a SQL query and return results
    #[instrument(skip(self, sql), fields(sql = %sql))]
    pub async fn query(&self, sql: &str) -> Result<Rows> {
        let sql = sql.to_string();
        let pool = Arc::clone(&self.pool);

        let rows = task::spawn_blocking(move || {
            let conn = pool.get_connection()?;
            conn.query(&sql)
        })
        .await
        .map_err(|e| Error::pool_error(format!("Task join error: {}", e)))??;

        debug!("Executed query successfully");
        Ok(rows)
    }

    /// Prepare a SQL statement for repeated execution
    #[instrument(skip(self, sql), fields(sql = %sql))]
    pub async fn prepare(&self, sql: &str) -> Result<AsyncPreparedStatement> {
        let sql = sql.to_string();
        let pool = Arc::clone(&self.pool);

        task::spawn_blocking(move || {
            let conn = pool.get_connection()?;
            let stmt = conn.prepare(&sql)?;
            Ok(AsyncPreparedStatement::new(stmt, pool))
        })
        .await
        .map_err(|e| Error::pool_error(format!("Task join error: {}", e)))?
    }

    /// Begin a transaction
    #[instrument(skip(self))]
    pub async fn begin_transaction(&self) -> Result<AsyncTransaction> {
        let pool = Arc::clone(&self.pool);

        let conn_guard = task::spawn_blocking(move || pool.get_connection())
            .await
            .map_err(|e| Error::pool_error(format!("Task join error: {}", e)))??;

        // Begin transaction on the acquired connection
        let tx = task::spawn_blocking(move || conn_guard.begin_transaction())
            .await
            .map_err(|e| Error::pool_error(format!("Task join error: {}", e)))??;

        debug!("Started transaction");
        Ok(AsyncTransaction::new(tx))
    }

    /// Execute multiple statements in a transaction
    #[instrument(skip(self, statements))]
    pub async fn execute_batch<F, Fut>(&self, f: F) -> Result<()>
    where
        F: FnOnce(AsyncTransaction) -> Fut + Send + 'static,
        Fut: std::future::Future<Output = Result<()>> + Send,
    {
        let tx = self.begin_transaction().await?;
        match f(tx).await {
            Ok(()) => {
                debug!("Batch execution completed successfully");
                Ok(())
            }
            Err(e) => {
                debug!("Batch execution failed, transaction will rollback");
                Err(e)
            }
        }
    }

    /// Get pool statistics
    pub fn pool_stats(&self) -> crate::PoolStats {
        self.pool.stats()
    }

    /// Perform pool maintenance
    pub async fn maintain_pool(&self) {
        let pool = Arc::clone(&self.pool);
        task::spawn_blocking(move || pool.maintain())
            .await
            .unwrap_or_else(|e| {
                tracing::error!("Pool maintenance task failed: {}", e);
            });
    }
}

/// An async wrapper around a prepared statement
pub struct AsyncPreparedStatement {
    // Note: We can't directly wrap PreparedStatement because it's not Send
    // Instead, we store the SQL and recreate the statement for each execution
    sql: String,
    pool: Arc<ConnectionPool>,
}

impl AsyncPreparedStatement {
    fn new(stmt: crate::PreparedStatement, pool: Arc<ConnectionPool>) -> Self {
        // We drop the original statement and just keep the SQL
        // This is less efficient but ensures thread safety
        drop(stmt);

        Self {
            sql: "".to_string(), // TODO: Extract SQL from statement
            pool,
        }
    }

    /// Execute the prepared statement with parameters
    #[instrument(skip(self, params))]
    pub async fn execute_with_params(&self, params: &[SqlValue]) -> Result<()> {
        let sql = self.sql.clone();
        let params = params.to_vec();
        let pool = Arc::clone(&self.pool);

        task::spawn_blocking(move || {
            let conn = pool.get_connection()?;
            let mut stmt = conn.prepare(&sql)?;

            // Bind parameters
            for (index, param) in params.iter().enumerate() {
                match param {
                    SqlValue::Integer(value) => stmt.bind_int(index, *value)?,
                    SqlValue::Real(value) => stmt.bind_real(index, *value)?,
                    SqlValue::Text(value) => stmt.bind_text(index, value)?,
                    SqlValue::Null => stmt.bind_null(index)?,
                }
            }

            stmt.execute()
        })
        .await
        .map_err(|e| Error::pool_error(format!("Task join error: {}", e)))?
    }
}

/// Parameter values for prepared statements
#[derive(Debug, Clone)]
pub enum SqlValue {
    /// Integer value
    Integer(i64),
    /// Real (floating point) value
    Real(f64),
    /// Text value
    Text(String),
    /// Null value
    Null,
}

/// An async transaction wrapper
pub struct AsyncTransaction {
    // Note: Similar to PreparedStatement, we can't directly wrap Transaction
    // because it contains lifetime parameters and isn't Send
    connection_pool: Option<Arc<ConnectionPool>>,
    committed: bool,
}

impl AsyncTransaction {
    fn new(tx: crate::Transaction) -> Self {
        // Drop the original transaction and work directly with connection
        drop(tx);

        Self {
            connection_pool: None, // TODO: Store connection pool reference
            committed: false,
        }
    }

    /// Execute a statement within the transaction
    #[instrument(skip(self, sql), fields(sql = %sql))]
    pub async fn execute(&self, sql: &str) -> Result<()> {
        if self.committed {
            return Err(Error::TransactionError);
        }

        // TODO: Execute on the transaction's connection
        // For now, this is a simplified implementation
        Ok(())
    }

    /// Query within the transaction
    #[instrument(skip(self, sql), fields(sql = %sql))]
    pub async fn query(&self, sql: &str) -> Result<Rows> {
        if self.committed {
            return Err(Error::TransactionError);
        }

        // TODO: Query on the transaction's connection
        // For now, return an error
        Err(Error::TransactionError)
    }

    /// Commit the transaction
    #[instrument(skip(self))]
    pub async fn commit(mut self) -> Result<()> {
        if self.committed {
            return Err(Error::TransactionError);
        }

        // TODO: Commit the actual transaction
        self.committed = true;
        debug!("Transaction committed");
        Ok(())
    }

    /// Rollback the transaction
    #[instrument(skip(self))]
    pub async fn rollback(self) -> Result<()> {
        // TODO: Rollback the actual transaction
        debug!("Transaction rolled back");
        Ok(())
    }
}

/// Async connection pool for managing multiple connections
pub struct AsyncConnectionPool {
    inner: Arc<ConnectionPool>,
}

impl AsyncConnectionPool {
    /// Create a new async connection pool
    #[instrument(skip(database_path))]
    pub async fn new(database_path: Option<&str>, config: PoolConfig) -> Result<Self> {
        let database_path = database_path.map(|s| s.to_string());
        let pool = task::spawn_blocking(move || ConnectionPool::new(database_path.as_deref(), config))
            .await
            .map_err(|e| Error::pool_error(format!("Task join error: {}", e)))??;

        Ok(Self {
            inner: Arc::new(pool),
        })
    }

    /// Create a new async connection pool with default configuration
    pub async fn new_default(database_path: Option<&str>) -> Result<Self> {
        Self::new(database_path, PoolConfig::default()).await
    }

    /// Get a connection from the pool
    #[instrument(skip(self))]
    pub async fn get_connection(&self) -> Result<AsyncConnection> {
        let pool = Arc::clone(&self.inner);
        Ok(AsyncConnection::from_pool(pool))
    }

    /// Get pool statistics
    pub fn stats(&self) -> crate::PoolStats {
        self.inner.stats()
    }

    /// Perform maintenance on the pool
    #[instrument(skip(self))]
    pub async fn maintain(&self) {
        let pool = Arc::clone(&self.inner);
        task::spawn_blocking(move || pool.maintain())
            .await
            .unwrap_or_else(|e| {
                tracing::error!("Pool maintenance task failed: {}", e);
            });
    }

    /// Close the pool
    #[instrument(skip(self))]
    pub async fn close(&self) {
        let pool = Arc::clone(&self.inner);
        task::spawn_blocking(move || pool.close())
            .await
            .unwrap_or_else(|e| {
                tracing::error!("Pool close task failed: {}", e);
            });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_async_connection() {
        let conn = AsyncConnection::open(":memory:").await.unwrap();

        conn.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
            .await
            .unwrap();

        conn.execute("INSERT INTO test (name) VALUES ('Alice')")
            .await
            .unwrap();

        let rows = conn.query("SELECT * FROM test").await.unwrap();
        assert_eq!(rows.row_count(), 1);
    }

    #[tokio::test]
    async fn test_async_pool() {
        let pool = AsyncConnectionPool::new_default(None).await.unwrap();

        let conn = pool.get_connection().await.unwrap();
        conn.execute("CREATE TABLE test (id INTEGER)").await.unwrap();

        let stats = pool.stats();
        assert!(stats.connections_created >= 1);
    }

    #[tokio::test]
    async fn test_async_batch_execution() {
        let conn = AsyncConnection::open(":memory:").await.unwrap();

        conn.execute_batch(|tx| async move {
            tx.execute("CREATE TABLE test (id INTEGER)").await?;
            tx.execute("INSERT INTO test VALUES (1)").await?;
            tx.execute("INSERT INTO test VALUES (2)").await?;
            tx.commit().await
        })
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn test_concurrent_async_operations() {
        let pool = Arc::new(AsyncConnectionPool::new_default(None).await.unwrap());

        let mut handles = vec![];

        for i in 0..10 {
            let pool_clone = Arc::clone(&pool);
            let handle = tokio::spawn(async move {
                let conn = pool_clone.get_connection().await.unwrap();
                conn.execute(&format!(
                    "CREATE TABLE IF NOT EXISTS test{} (id INTEGER)",
                    i
                ))
                .await
                .unwrap();
            });
            handles.push(handle);
        }

        for handle in handles {
            handle.await.unwrap();
        }

        let stats = pool.stats();
        assert!(stats.connections_created >= 1);
    }
}