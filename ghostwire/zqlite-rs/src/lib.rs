//! # ZQLite Rust Bindings
//!
//! High-performance Rust bindings for ZQLite, an embedded SQL database with
//! post-quantum cryptography support.
//!
//! ## Features
//!
//! - Memory-safe FFI bindings to ZQLite
//! - Async/await support with Tokio integration
//! - Connection pooling for high-concurrency scenarios
//! - Observability with tracing and metrics
//! - Post-quantum cryptographic features
//!
//! ## Example
//!
//! ```rust,no_run
//! use zqlite_rs::{Connection, Result};
//!
//! #[tokio::main]
//! async fn main() -> Result<()> {
//!     let conn = Connection::open(":memory:")?;
//!
//!     conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")?;
//!     conn.execute("INSERT INTO users (name) VALUES ('Alice')")?;
//!
//!     let rows = conn.query("SELECT * FROM users")?;
//!     for row in rows {
//!         println!("ID: {}, Name: {}", row.get::<i64>(0)?, row.get::<String>(1)?);
//!     }
//!
//!     Ok(())
//! }
//! ```

#![warn(missing_docs)]
#![warn(rust_2018_idioms)]

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;
use std::sync::Arc;

pub use error::{Error, Result};
pub use pool::{ConnectionPool, PoolConfig, PoolStats};
pub use row::{Row, Rows, FromSql};
pub use metrics::{ZQLiteMetrics, TransactionOutcome, Timer, PrometheusConfig, init_prometheus_exporter};

#[cfg(feature = "async")]
pub use async_connection::{AsyncConnection, AsyncConnectionPool, AsyncPreparedStatement, AsyncTransaction, SqlValue};

mod error;
mod pool;
mod row;
mod metrics;

#[cfg(feature = "async")]
mod async_connection;

// Include the generated FFI bindings
include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

/// A ZQLite database connection
pub struct Connection {
    inner: *mut zqlite_connection_t,
    _marker: std::marker::PhantomData<zqlite_connection_t>,
}

impl Connection {
    /// Open a database connection
    ///
    /// # Arguments
    ///
    /// * `path` - Database file path, or ":memory:" for in-memory database
    ///
    /// # Example
    ///
    /// ```rust,no_run
    /// use zqlite_rs::Connection;
    ///
    /// let conn = Connection::open("example.db")?;
    /// # Ok::<(), zqlite_rs::Error>(())
    /// ```
    pub fn open(path: &str) -> Result<Self> {
        let path_cstr = CString::new(path).map_err(|_| Error::InvalidPath)?;

        let conn_ptr = unsafe { zqlite_open(path_cstr.as_ptr()) };

        if conn_ptr.is_null() {
            return Err(Error::ConnectionFailed);
        }

        Ok(Connection {
            inner: conn_ptr,
            _marker: std::marker::PhantomData,
        })
    }

    /// Execute a SQL statement without returning results
    ///
    /// # Arguments
    ///
    /// * `sql` - SQL statement to execute
    ///
    /// # Example
    ///
    /// ```rust,no_run
    /// # use zqlite_rs::Connection;
    /// # let conn = Connection::open(":memory:")?;
    /// conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")?;
    /// conn.execute("INSERT INTO users (name) VALUES ('Alice')")?;
    /// # Ok::<(), zqlite_rs::Error>(())
    /// ```
    pub fn execute(&self, sql: &str) -> Result<()> {
        let sql_cstr = CString::new(sql).map_err(|_| Error::InvalidSql)?;

        let result = unsafe { zqlite_execute(self.inner, sql_cstr.as_ptr()) };

        if result != ZQLITE_OK as c_int {
            return Err(self.get_last_error());
        }

        Ok(())
    }

    /// Execute a SQL query and return results
    ///
    /// # Arguments
    ///
    /// * `sql` - SQL query to execute
    ///
    /// # Example
    ///
    /// ```rust,no_run
    /// # use zqlite_rs::Connection;
    /// # let conn = Connection::open(":memory:")?;
    /// # conn.execute("CREATE TABLE users (id INTEGER, name TEXT)")?;
    /// # conn.execute("INSERT INTO users VALUES (1, 'Alice')")?;
    /// let rows = conn.query("SELECT id, name FROM users")?;
    /// for row in rows {
    ///     let id: i64 = row.get(0)?;
    ///     let name: String = row.get(1)?;
    ///     println!("ID: {}, Name: {}", id, name);
    /// }
    /// # Ok::<(), zqlite_rs::Error>(())
    /// ```
    pub fn query(&self, sql: &str) -> Result<Rows> {
        let sql_cstr = CString::new(sql).map_err(|_| Error::InvalidSql)?;

        let result_ptr = unsafe { zqlite_query(self.inner, sql_cstr.as_ptr()) };

        if result_ptr.is_null() {
            return Err(self.get_last_error());
        }

        Ok(Rows::new(result_ptr))
    }

    /// Prepare a SQL statement for repeated execution
    ///
    /// # Arguments
    ///
    /// * `sql` - SQL statement to prepare
    ///
    /// # Example
    ///
    /// ```rust,no_run
    /// # use zqlite_rs::Connection;
    /// # let conn = Connection::open(":memory:")?;
    /// # conn.execute("CREATE TABLE users (id INTEGER, name TEXT)")?;
    /// let mut stmt = conn.prepare("INSERT INTO users (name) VALUES (?)")?;
    /// stmt.bind_text(0, "Alice")?;
    /// stmt.execute()?;
    /// # Ok::<(), zqlite_rs::Error>(())
    /// ```
    pub fn prepare(&self, sql: &str) -> Result<PreparedStatement> {
        let sql_cstr = CString::new(sql).map_err(|_| Error::InvalidSql)?;

        let stmt_ptr = unsafe { zqlite_prepare(self.inner, sql_cstr.as_ptr()) };

        if stmt_ptr.is_null() {
            return Err(self.get_last_error());
        }

        Ok(PreparedStatement::new(stmt_ptr))
    }

    /// Begin a transaction
    pub fn begin_transaction(&self) -> Result<Transaction<'_>> {
        let result = unsafe { zqlite_begin_transaction(self.inner) };

        if result != ZQLITE_OK as c_int {
            return Err(self.get_last_error());
        }

        Ok(Transaction::new(self))
    }

    /// Get the last error message
    fn get_last_error(&self) -> Error {
        let error_msg = unsafe {
            let msg_ptr = zqlite_errmsg(self.inner);
            if msg_ptr.is_null() {
                return Error::Unknown;
            }
            CStr::from_ptr(msg_ptr).to_string_lossy().into_owned()
        };

        Error::Database(error_msg)
    }

    /// Get ZQLite version
    pub fn version() -> &'static str {
        unsafe {
            let version_ptr = zqlite_version();
            CStr::from_ptr(version_ptr).to_str().unwrap_or("unknown")
        }
    }

    /// Get the number of rows affected by the last operation
    pub fn changes(&self) -> i64 {
        unsafe { zqlite_changes(self.inner) as i64 }
    }

    /// Get the last inserted row ID
    pub fn last_insert_rowid(&self) -> i64 {
        unsafe { zqlite_last_insert_rowid(self.inner) }
    }
}

impl Drop for Connection {
    fn drop(&mut self) {
        unsafe {
            zqlite_close(self.inner);
        }
    }
}

// Safety: Connection operations are thread-safe in ZQLite
unsafe impl Send for Connection {}
unsafe impl Sync for Connection {}

/// A prepared SQL statement
pub struct PreparedStatement {
    inner: *mut zqlite_stmt_t,
    _marker: std::marker::PhantomData<zqlite_stmt_t>,
}

impl PreparedStatement {
    fn new(stmt: *mut zqlite_stmt_t) -> Self {
        Self {
            inner: stmt,
            _marker: std::marker::PhantomData,
        }
    }

    /// Bind an integer parameter
    pub fn bind_int(&mut self, index: usize, value: i64) -> Result<()> {
        let result = unsafe { zqlite_bind_int(self.inner, index as c_int, value) };

        if result != ZQLITE_OK as c_int {
            return Err(Error::BindError);
        }

        Ok(())
    }

    /// Bind a text parameter
    pub fn bind_text(&mut self, index: usize, value: &str) -> Result<()> {
        let value_cstr = CString::new(value).map_err(|_| Error::InvalidSql)?;
        let result = unsafe { zqlite_bind_text(self.inner, index as c_int, value_cstr.as_ptr()) };

        if result != ZQLITE_OK as c_int {
            return Err(Error::BindError);
        }

        Ok(())
    }

    /// Bind a real (float) parameter
    pub fn bind_real(&mut self, index: usize, value: f64) -> Result<()> {
        let result = unsafe { zqlite_bind_real(self.inner, index as c_int, value) };

        if result != ZQLITE_OK as c_int {
            return Err(Error::BindError);
        }

        Ok(())
    }

    /// Bind a null parameter
    pub fn bind_null(&mut self, index: usize) -> Result<()> {
        let result = unsafe { zqlite_bind_null(self.inner, index as c_int) };

        if result != ZQLITE_OK as c_int {
            return Err(Error::BindError);
        }

        Ok(())
    }

    /// Execute the prepared statement
    pub fn execute(&mut self) -> Result<()> {
        let result = unsafe { zqlite_step(self.inner) };

        match result {
            x if x == ZQLITE_DONE as c_int => Ok(()),
            x if x == ZQLITE_ROW as c_int => Ok(()), // Has results but we're not returning them
            _ => Err(Error::ExecutionError),
        }
    }

    /// Reset the prepared statement for re-execution
    pub fn reset(&mut self) -> Result<()> {
        let result = unsafe { zqlite_reset(self.inner) };

        if result != ZQLITE_OK as c_int {
            return Err(Error::ResetError);
        }

        Ok(())
    }
}

impl Drop for PreparedStatement {
    fn drop(&mut self) {
        unsafe {
            zqlite_finalize(self.inner);
        }
    }
}

/// A database transaction
pub struct Transaction<'conn> {
    connection: &'conn Connection,
    committed: bool,
}

impl<'conn> Transaction<'conn> {
    fn new(connection: &'conn Connection) -> Self {
        Self {
            connection,
            committed: false,
        }
    }

    /// Commit the transaction
    pub fn commit(mut self) -> Result<()> {
        let result = unsafe { zqlite_commit_transaction(self.connection.inner) };

        if result != ZQLITE_OK as c_int {
            return Err(Error::TransactionError);
        }

        self.committed = true;
        Ok(())
    }

    /// Rollback the transaction
    pub fn rollback(self) -> Result<()> {
        let result = unsafe { zqlite_rollback_transaction(self.connection.inner) };

        if result != ZQLITE_OK as c_int {
            return Err(Error::TransactionError);
        }

        Ok(())
    }

    /// Execute a statement within the transaction
    pub fn execute(&self, sql: &str) -> Result<()> {
        self.connection.execute(sql)
    }

    /// Query within the transaction
    pub fn query(&self, sql: &str) -> Result<Rows> {
        self.connection.query(sql)
    }
}

impl<'conn> Drop for Transaction<'conn> {
    fn drop(&mut self) {
        if !self.committed {
            // Auto-rollback on drop if not committed
            let _ = unsafe { zqlite_rollback_transaction(self.connection.inner) };
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_open_memory_database() {
        let conn = Connection::open(":memory:").unwrap();
        assert!(!conn.inner.is_null());
    }

    #[test]
    fn test_create_table_and_insert() {
        let conn = Connection::open(":memory:").unwrap();

        conn.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)").unwrap();
        conn.execute("INSERT INTO test (name) VALUES ('test_user')").unwrap();

        assert_eq!(conn.changes(), 1);
        assert!(conn.last_insert_rowid() > 0);
    }

    #[test]
    fn test_prepared_statements() {
        let conn = Connection::open(":memory:").unwrap();

        conn.execute("CREATE TABLE test (id INTEGER, name TEXT)").unwrap();

        let mut stmt = conn.prepare("INSERT INTO test VALUES (?, ?)").unwrap();
        stmt.bind_int(0, 42).unwrap();
        stmt.bind_text(1, "test").unwrap();
        stmt.execute().unwrap();

        assert_eq!(conn.changes(), 1);
    }

    #[test]
    fn test_transaction() {
        let conn = Connection::open(":memory:").unwrap();

        conn.execute("CREATE TABLE test (id INTEGER)").unwrap();

        let tx = conn.begin_transaction().unwrap();
        tx.execute("INSERT INTO test VALUES (1)").unwrap();
        tx.execute("INSERT INTO test VALUES (2)").unwrap();
        tx.commit().unwrap();

        // Verify data was committed
        let rows = conn.query("SELECT COUNT(*) FROM test").unwrap();
        // Note: We'd need to implement row iteration to fully test this
    }

    #[test]
    fn test_version() {
        let version = Connection::version();
        assert!(!version.is_empty());
        println!("ZQLite version: {}", version);
    }
}