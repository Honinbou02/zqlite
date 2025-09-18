//! Error types for ZQLite Rust bindings

use std::fmt;

/// Result type alias for ZQLite operations
pub type Result<T> = std::result::Result<T, Error>;

/// ZQLite error types
#[derive(Debug, Clone, thiserror::Error)]
pub enum Error {
    /// Database operation failed
    #[error("Database error: {0}")]
    Database(String),

    /// Connection failed to open
    #[error("Failed to open database connection")]
    ConnectionFailed,

    /// Invalid database path
    #[error("Invalid database path")]
    InvalidPath,

    /// Invalid SQL statement
    #[error("Invalid SQL statement")]
    InvalidSql,

    /// Parameter binding failed
    #[error("Failed to bind parameter")]
    BindError,

    /// Query execution failed
    #[error("Query execution failed")]
    ExecutionError,

    /// Statement reset failed
    #[error("Failed to reset statement")]
    ResetError,

    /// Transaction operation failed
    #[error("Transaction operation failed")]
    TransactionError,

    /// Row access error
    #[error("Row access error: {0}")]
    RowError(String),

    /// Type conversion error
    #[error("Type conversion error: expected {expected}, got {actual}")]
    TypeMismatch {
        /// Expected type
        expected: String,
        /// Actual type
        actual: String,
    },

    /// Connection pool error
    #[error("Connection pool error: {0}")]
    PoolError(String),

    /// Unknown error
    #[error("Unknown error")]
    Unknown,

    /// I/O error
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    /// Null pointer encountered
    #[error("Unexpected null pointer")]
    NullPointer,

    /// Index out of bounds
    #[error("Index out of bounds: {index}")]
    IndexOutOfBounds {
        /// The invalid index
        index: usize,
    },
}

impl Error {
    /// Create a new database error
    pub fn database<S: Into<String>>(message: S) -> Self {
        Error::Database(message.into())
    }

    /// Create a new row error
    pub fn row_error<S: Into<String>>(message: S) -> Self {
        Error::RowError(message.into())
    }

    /// Create a new type mismatch error
    pub fn type_mismatch<S1: Into<String>, S2: Into<String>>(expected: S1, actual: S2) -> Self {
        Error::TypeMismatch {
            expected: expected.into(),
            actual: actual.into(),
        }
    }

    /// Create a new pool error
    pub fn pool_error<S: Into<String>>(message: S) -> Self {
        Error::PoolError(message.into())
    }

    /// Create an index out of bounds error
    pub fn index_out_of_bounds(index: usize) -> Self {
        Error::IndexOutOfBounds { index }
    }

    /// Check if this error is recoverable
    pub fn is_recoverable(&self) -> bool {
        match self {
            Error::Database(_) => false,
            Error::ConnectionFailed => false,
            Error::InvalidPath => false,
            Error::InvalidSql => true,
            Error::BindError => true,
            Error::ExecutionError => true,
            Error::ResetError => true,
            Error::TransactionError => false,
            Error::RowError(_) => true,
            Error::TypeMismatch { .. } => true,
            Error::PoolError(_) => true,
            Error::Unknown => false,
            Error::Io(_) => false,
            Error::NullPointer => false,
            Error::IndexOutOfBounds { .. } => true,
        }
    }
}

/// Convert ZQLite error codes to Rust errors
impl From<i32> for Error {
    fn from(code: i32) -> Self {
        use crate::{
            ZQLITE_AUTH, ZQLITE_BUSY, ZQLITE_CANTOPEN, ZQLITE_CONSTRAINT, ZQLITE_CORRUPT,
            ZQLITE_ERROR, ZQLITE_FULL, ZQLITE_INTERNAL, ZQLITE_IOERR, ZQLITE_LOCKED,
            ZQLITE_MISMATCH, ZQLITE_MISUSE, ZQLITE_NOLFS, ZQLITE_NOMEM, ZQLITE_NOTADB,
            ZQLITE_NOTFOUND, ZQLITE_OK, ZQLITE_PERM, ZQLITE_PROTOCOL, ZQLITE_RANGE,
            ZQLITE_READONLY, ZQLITE_SCHEMA, ZQLITE_TOOBIG,
        };

        match code {
            x if x == ZQLITE_OK as i32 => return Error::Unknown, // Shouldn't happen
            x if x == ZQLITE_ERROR as i32 => Error::Database("Generic error".to_string()),
            x if x == ZQLITE_INTERNAL as i32 => Error::Database("Internal logic error".to_string()),
            x if x == ZQLITE_PERM as i32 => Error::Database("Access permission denied".to_string()),
            x if x == ZQLITE_BUSY as i32 => Error::Database("Database file is locked".to_string()),
            x if x == ZQLITE_LOCKED as i32 => Error::Database("Database table is locked".to_string()),
            x if x == ZQLITE_NOMEM as i32 => Error::Database("Out of memory".to_string()),
            x if x == ZQLITE_READONLY as i32 => {
                Error::Database("Attempt to write readonly database".to_string())
            }
            x if x == ZQLITE_IOERR as i32 => Error::Database("Disk I/O error".to_string()),
            x if x == ZQLITE_CORRUPT as i32 => {
                Error::Database("Database image is malformed".to_string())
            }
            x if x == ZQLITE_NOTFOUND as i32 => Error::Database("Item not found".to_string()),
            x if x == ZQLITE_FULL as i32 => {
                Error::Database("Insertion failed because database is full".to_string())
            }
            x if x == ZQLITE_CANTOPEN as i32 => {
                Error::Database("Unable to open database file".to_string())
            }
            x if x == ZQLITE_PROTOCOL as i32 => {
                Error::Database("Database lock protocol error".to_string())
            }
            x if x == ZQLITE_SCHEMA as i32 => {
                Error::Database("Database schema changed".to_string())
            }
            x if x == ZQLITE_TOOBIG as i32 => {
                Error::Database("String or BLOB exceeds size limit".to_string())
            }
            x if x == ZQLITE_CONSTRAINT as i32 => {
                Error::Database("Constraint violation".to_string())
            }
            x if x == ZQLITE_MISMATCH as i32 => Error::Database("Data type mismatch".to_string()),
            x if x == ZQLITE_MISUSE as i32 => {
                Error::Database("Library used incorrectly".to_string())
            }
            x if x == ZQLITE_NOLFS as i32 => {
                Error::Database("OS features not supported".to_string())
            }
            x if x == ZQLITE_AUTH as i32 => Error::Database("Authorization denied".to_string()),
            x if x == ZQLITE_RANGE as i32 => {
                Error::Database("Parameter out of range".to_string())
            }
            x if x == ZQLITE_NOTADB as i32 => {
                Error::Database("File opened that is not a database file".to_string())
            }
            _ => Error::Database(format!("Unknown error code: {}", code)),
        }
    }
}