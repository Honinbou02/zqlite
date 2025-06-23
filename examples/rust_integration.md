# Rust Integration Example for Jarvis AI Agent

Add this to your Rust project's `Cargo.toml`:

```toml
[dependencies]
libc = "0.2"

[build-dependencies]
cc = "1.0"
```

Create `build.rs` in your Rust project root:

```rust
fn main() {
    // Link to zqlite static library
    println!("cargo:rustc-link-lib=static=zqlite");
    println!("cargo:rustc-link-search=native=/path/to/zqlite/zig-out/lib");
    
    // Include header
    println!("cargo:rerun-if-changed=/path/to/zqlite/include/zqlite.h");
}
```

Create `src/zqlite.rs`:

```rust
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;

// Raw FFI bindings
extern "C" {
    fn zqlite_open(path: *const c_char) -> *mut c_void;
    fn zqlite_close(conn: *mut c_void) -> c_int;
    fn zqlite_execute(conn: *mut c_void, sql: *const c_char) -> c_int;
    fn zqlite_query(conn: *mut c_void, sql: *const c_char) -> *mut c_void;
    fn zqlite_result_row_count(result: *mut c_void) -> c_int;
    fn zqlite_result_column_count(result: *mut c_void) -> c_int;
    fn zqlite_result_get_text(result: *mut c_void, row: c_int, column: c_int) -> *const c_char;
    fn zqlite_result_free(result: *mut c_void);
    fn zqlite_prepare(conn: *mut c_void, sql: *const c_char) -> *mut c_void;
    fn zqlite_bind_int(stmt: *mut c_void, index: c_int, value: i64) -> c_int;
    fn zqlite_bind_text(stmt: *mut c_void, index: c_int, value: *const c_char) -> c_int;
    fn zqlite_step(stmt: *mut c_void) -> c_int;
    fn zqlite_finalize(stmt: *mut c_void) -> c_int;
    fn zqlite_version() -> *const c_char;
}

// Safe Rust wrapper
pub struct ZqliteConnection {
    conn: *mut c_void,
}

impl ZqliteConnection {
    pub fn open(path: &str) -> Result<Self, String> {
        let c_path = CString::new(path).map_err(|_| "Invalid path")?;
        let conn = unsafe { zqlite_open(c_path.as_ptr()) };
        
        if conn.is_null() {
            Err("Failed to open database".to_string())
        } else {
            Ok(ZqliteConnection { conn })
        }
    }
    
    pub fn execute(&self, sql: &str) -> Result<(), String> {
        let c_sql = CString::new(sql).map_err(|_| "Invalid SQL")?;
        let result = unsafe { zqlite_execute(self.conn, c_sql.as_ptr()) };
        
        if result == 0 {
            Ok(())
        } else {
            Err(format!("SQL execution failed: {}", result))
        }
    }
    
    pub fn query(&self, sql: &str) -> Result<QueryResult, String> {
        let c_sql = CString::new(sql).map_err(|_| "Invalid SQL")?;
        let result = unsafe { zqlite_query(self.conn, c_sql.as_ptr()) };
        
        if result.is_null() {
            Err("Query failed".to_string())
        } else {
            Ok(QueryResult { result })
        }
    }
    
    pub fn prepare(&self, sql: &str) -> Result<PreparedStatement, String> {
        let c_sql = CString::new(sql).map_err(|_| "Invalid SQL")?;
        let stmt = unsafe { zqlite_prepare(self.conn, c_sql.as_ptr()) };
        
        if stmt.is_null() {
            Err("Failed to prepare statement".to_string())
        } else {
            Ok(PreparedStatement { stmt })
        }
    }
}

impl Drop for ZqliteConnection {
    fn drop(&mut self) {
        unsafe {
            zqlite_close(self.conn);
        }
    }
}

pub struct QueryResult {
    result: *mut c_void,
}

impl QueryResult {
    pub fn row_count(&self) -> i32 {
        unsafe { zqlite_result_row_count(self.result) }
    }
    
    pub fn column_count(&self) -> i32 {
        unsafe { zqlite_result_column_count(self.result) }
    }
    
    pub fn get_text(&self, row: i32, column: i32) -> Option<String> {
        let c_str = unsafe { zqlite_result_get_text(self.result, row, column) };
        if c_str.is_null() {
            None
        } else {
            unsafe {
                Some(CStr::from_ptr(c_str).to_string_lossy().into_owned())
            }
        }
    }
}

impl Drop for QueryResult {
    fn drop(&mut self) {
        unsafe {
            zqlite_result_free(self.result);
        }
    }
}

pub struct PreparedStatement {
    stmt: *mut c_void,
}

impl PreparedStatement {
    pub fn bind_int(&self, index: i32, value: i64) -> Result<(), String> {
        let result = unsafe { zqlite_bind_int(self.stmt, index, value) };
        if result == 0 {
            Ok(())
        } else {
            Err(format!("Failed to bind int: {}", result))
        }
    }
    
    pub fn bind_text(&self, index: i32, value: &str) -> Result<(), String> {
        let c_value = CString::new(value).map_err(|_| "Invalid text")?;
        let result = unsafe { zqlite_bind_text(self.stmt, index, c_value.as_ptr()) };
        if result == 0 {
            Ok(())
        } else {
            Err(format!("Failed to bind text: {}", result))
        }
    }
    
    pub fn execute(&self) -> Result<(), String> {
        let result = unsafe { zqlite_step(self.stmt) };
        if result == 101 { // ZQLITE_DONE
            Ok(())
        } else {
            Err(format!("Statement execution failed: {}", result))
        }
    }
}

impl Drop for PreparedStatement {
    fn drop(&mut self) {
        unsafe {
            zqlite_finalize(self.stmt);
        }
    }
}

// Utility functions
pub fn version() -> String {
    unsafe {
        CStr::from_ptr(zqlite_version()).to_string_lossy().into_owned()
    }
}

// Example usage for Jarvis AI Agent
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_ai_agent_session_storage() {
        let db = ZqliteConnection::open(":memory:").unwrap();
        
        // Create AI agent session table
        db.execute(r#"
            CREATE TABLE ai_sessions (
                id INTEGER PRIMARY KEY,
                user_id INTEGER,
                session_data TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                metadata JSON
            )
        "#).unwrap();
        
        // Insert session with prepared statement
        let stmt = db.prepare("INSERT INTO ai_sessions (user_id, session_data, metadata) VALUES (?, ?, ?)").unwrap();
        stmt.bind_int(0, 123).unwrap();
        stmt.bind_text(1, "conversation_context").unwrap();
        stmt.bind_text(2, r#"{"model": "gpt-4", "temperature": 0.7}"#).unwrap();
        stmt.execute().unwrap();
        
        // Query sessions
        let result = db.query("SELECT id, user_id, metadata FROM ai_sessions WHERE user_id = 123").unwrap();
        assert_eq!(result.row_count(), 1);
        
        let metadata = result.get_text(0, 2).unwrap();
        assert!(metadata.contains("gpt-4"));
    }
    
    #[test]
    fn test_vpn_node_storage() {
        let db = ZqliteConnection::open(":memory:").unwrap();
        
        // Create VPN nodes table
        db.execute(r#"
            CREATE TABLE vpn_nodes (
                node_id TEXT PRIMARY KEY,
                ip_address TEXT NOT NULL,
                port INTEGER,
                region TEXT,
                capacity INTEGER,
                status TEXT DEFAULT 'active'
            )
        "#).unwrap();
        
        // Insert VPN node
        let stmt = db.prepare("INSERT INTO vpn_nodes VALUES (?, ?, ?, ?, ?, ?)").unwrap();
        stmt.bind_text(0, "node_us_east_1").unwrap();
        stmt.bind_text(1, "192.168.1.100").unwrap();
        stmt.bind_int(2, 1194).unwrap();
        stmt.bind_text(3, "us-east").unwrap();
        stmt.bind_int(4, 1000).unwrap();
        stmt.bind_text(5, "active").unwrap();
        stmt.execute().unwrap();
        
        // Query by region
        let result = db.query("SELECT node_id, ip_address FROM vpn_nodes WHERE region = 'us-east'").unwrap();
        assert_eq!(result.row_count(), 1);
    }
    
    #[test]
    fn test_crypto_wallet_storage() {
        let db = ZqliteConnection::open(":memory:").unwrap();
        
        // Create crypto wallets table
        db.execute(r#"
            CREATE TABLE crypto_wallets (
                wallet_id TEXT PRIMARY KEY,
                address TEXT UNIQUE NOT NULL,
                balance REAL DEFAULT 0.0,
                currency TEXT,
                encrypted_private_key TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        "#).unwrap();
        
        // Insert wallet
        let stmt = db.prepare("INSERT INTO crypto_wallets VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)").unwrap();
        stmt.bind_text(0, "wallet_1").unwrap();
        stmt.bind_text(1, "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh").unwrap();
        stmt.bind_text(2, "0.05").unwrap();
        stmt.bind_text(3, "BTC").unwrap();
        stmt.bind_text(4, "encrypted_key_data").unwrap();
        stmt.execute().unwrap();
        
        // Query wallet
        let result = db.query("SELECT address, balance FROM crypto_wallets WHERE currency = 'BTC'").unwrap();
        assert_eq!(result.row_count(), 1);
    }
}
```

## Usage in Jarvis AI Agent

```rust
use zqlite::{ZqliteConnection, PreparedStatement};

pub struct JarvisStorage {
    db: ZqliteConnection,
}

impl JarvisStorage {
    pub fn new(db_path: &str) -> Result<Self, String> {
        let db = ZqliteConnection::open(db_path)?;
        
        // Initialize schema
        db.execute(r#"
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY,
                user_id TEXT,
                message TEXT,
                response TEXT,
                context JSON,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            
            CREATE TABLE IF NOT EXISTS user_preferences (
                user_id TEXT PRIMARY KEY,
                settings JSON,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            
            CREATE INDEX IF NOT EXISTS idx_conv_user ON conversations(user_id);
            CREATE INDEX IF NOT EXISTS idx_conv_time ON conversations(timestamp);
        "#)?;
        
        Ok(JarvisStorage { db })
    }
    
    pub fn store_conversation(&self, user_id: &str, message: &str, response: &str, context: &str) -> Result<(), String> {
        let stmt = self.db.prepare("INSERT INTO conversations (user_id, message, response, context) VALUES (?, ?, ?, ?)")?;
        stmt.bind_text(0, user_id)?;
        stmt.bind_text(1, message)?;
        stmt.bind_text(2, response)?;
        stmt.bind_text(3, context)?;
        stmt.execute()
    }
    
    pub fn get_conversation_history(&self, user_id: &str, limit: i32) -> Result<Vec<(String, String)>, String> {
        let sql = format!("SELECT message, response FROM conversations WHERE user_id = '{}' ORDER BY timestamp DESC LIMIT {}", user_id, limit);
        let result = self.db.query(&sql)?;
        
        let mut conversations = Vec::new();
        for i in 0..result.row_count() {
            let message = result.get_text(i, 0).unwrap_or_default();
            let response = result.get_text(i, 1).unwrap_or_default();
            conversations.push((message, response));
        }
        
        Ok(conversations)
    }
}
