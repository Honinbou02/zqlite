const std = @import("std");
const zqlite = @import("zqlite");

/// C FFI interface for zqlite
/// Enables integration with Rust, Python, and other languages

// Opaque handles for C API
const zqlite_connection_t = anyopaque;
const zqlite_result_t = anyopaque;
const zqlite_stmt_t = anyopaque;

/// Error codes for C API
pub const ZQLITE_OK = 0;
pub const ZQLITE_ERROR = 1;
pub const ZQLITE_BUSY = 2;
pub const ZQLITE_LOCKED = 3;
pub const ZQLITE_NOMEM = 4;
pub const ZQLITE_READONLY = 5;
pub const ZQLITE_MISUSE = 6;
pub const ZQLITE_NOLFS = 7;
pub const ZQLITE_AUTH = 8;
pub const ZQLITE_FORMAT = 9;
pub const ZQLITE_RANGE = 10;
pub const ZQLITE_NOTADB = 11;

/// Result structure for queries
const QueryResult = struct {
    rows: [][]?[]const u8,
    column_count: u32,
    row_count: u32,
    error_message: ?[]const u8,
};

// Global allocator for C API (TODO: make this configurable)
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const c_allocator = gpa.allocator();

/// Open a database connection
export fn zqlite_open(path: [*:0]const u8) ?*zqlite_connection_t {
    const path_slice = std.mem.span(path);

    const conn = if (std.mem.eql(u8, path_slice, ":memory:"))
        zqlite.openMemory(c_allocator) catch return null
    else
        zqlite.open(c_allocator, path_slice) catch return null;

    return @as(*zqlite_connection_t, @ptrCast(conn));
}

/// Close a database connection
export fn zqlite_close(conn: ?*zqlite_connection_t) void {
    if (conn) |c| {
        const connection: *zqlite.db.Connection = @ptrCast(@alignCast(c));
        connection.close();
    }
}

/// Execute a SQL statement (no result expected)
export fn zqlite_execute(conn: ?*zqlite_connection_t, sql: [*:0]const u8) c_int {
    if (conn == null) return ZQLITE_MISUSE;

    const connection: *zqlite.db.Connection = @ptrCast(@alignCast(conn.?));
    const sql_slice = std.mem.span(sql);

    connection.execute(sql_slice) catch return ZQLITE_ERROR;
    return ZQLITE_OK;
}

/// Execute a SQL query and return results
export fn zqlite_query(conn: ?*zqlite_connection_t, sql: [*:0]const u8) ?*zqlite_result_t {
    if (conn == null) return null;

    const connection: *zqlite.db.Connection = @ptrCast(@alignCast(conn.?));
    const sql_slice = std.mem.span(sql);

    // For now, we'll create a simple result structure
    // TODO: Implement proper result handling with row iteration
    const result = c_allocator.create(QueryResult) catch return null;
    result.* = QueryResult{
        .rows = &[_][]?[]const u8{},
        .column_count = 0,
        .row_count = 0,
        .error_message = null,
    };

    // Execute the query (for now just validate syntax)
    connection.execute(sql_slice) catch {
        result.error_message = c_allocator.dupe(u8, "Query execution failed") catch null;
        return @as(*zqlite_result_t, @ptrCast(result));
    };

    return @as(*zqlite_result_t, @ptrCast(result));
}

/// Get the number of rows in a result
export fn zqlite_result_row_count(result: ?*zqlite_result_t) c_int {
    if (result == null) return -1;

    const query_result: *QueryResult = @ptrCast(@alignCast(result.?));
    return @intCast(query_result.row_count);
}

/// Get the number of columns in a result
export fn zqlite_result_column_count(result: ?*zqlite_result_t) c_int {
    if (result == null) return -1;

    const query_result: *QueryResult = @ptrCast(@alignCast(result.?));
    return @intCast(query_result.column_count);
}

/// Get a cell value from the result
export fn zqlite_result_get_text(result: ?*zqlite_result_t, row: c_int, column: c_int) ?[*:0]const u8 {
    if (result == null) return null;

    const query_result: *QueryResult = @ptrCast(@alignCast(result.?));

    if (row < 0 or column < 0) return null;
    if (row >= query_result.row_count or column >= query_result.column_count) return null;

    const row_data = query_result.rows[@intCast(row)];
    const cell_data = row_data[@intCast(column)];

    if (cell_data) |data| {
        // Convert to null-terminated string
        const c_str = c_allocator.dupeZ(u8, data) catch return null;
        return c_str.ptr;
    }

    return null;
}

/// Free a result
export fn zqlite_result_free(result: ?*zqlite_result_t) void {
    if (result) |r| {
        const query_result: *QueryResult = @ptrCast(@alignCast(r));

        // Free rows and columns
        for (query_result.rows) |row| {
            for (row) |cell| {
                if (cell) |data| {
                    c_allocator.free(data);
                }
            }
            c_allocator.free(row);
        }
        c_allocator.free(query_result.rows);

        if (query_result.error_message) |msg| {
            c_allocator.free(msg);
        }

        c_allocator.destroy(query_result);
    }
}

/// Prepare a SQL statement
export fn zqlite_prepare(conn: ?*zqlite_connection_t, sql: [*:0]const u8) ?*zqlite_stmt_t {
    if (conn == null) return null;

    const connection: *zqlite.db.Connection = @ptrCast(@alignCast(conn.?));
    const sql_slice = std.mem.span(sql);

    const stmt = connection.prepare(sql_slice) catch return null;
    return @as(*zqlite_stmt_t, @ptrCast(stmt));
}

/// Bind an integer parameter
export fn zqlite_bind_int(stmt: ?*zqlite_stmt_t, index: c_int, value: i64) c_int {
    if (stmt == null) return ZQLITE_MISUSE;

    const statement: *zqlite.db.PreparedStatement = @ptrCast(@alignCast(stmt.?));
    const storage_value = zqlite.storage.Value{ .Integer = value };

    statement.bindParameter(@intCast(index), storage_value) catch return ZQLITE_ERROR;
    return ZQLITE_OK;
}

/// Bind a text parameter
export fn zqlite_bind_text(stmt: ?*zqlite_stmt_t, index: c_int, value: [*:0]const u8) c_int {
    if (stmt == null) return ZQLITE_MISUSE;

    const statement: *zqlite.db.PreparedStatement = @ptrCast(@alignCast(stmt.?));
    const text_value = std.mem.span(value);
    const owned_text = c_allocator.dupe(u8, text_value) catch return ZQLITE_NOMEM;
    const storage_value = zqlite.storage.Value{ .Text = owned_text };

    statement.bindParameter(@intCast(index), storage_value) catch return ZQLITE_ERROR;
    return ZQLITE_OK;
}

/// Bind a real (float) parameter
export fn zqlite_bind_real(stmt: ?*zqlite_stmt_t, index: c_int, value: f64) c_int {
    if (stmt == null) return ZQLITE_MISUSE;

    const statement: *zqlite.db.PreparedStatement = @ptrCast(@alignCast(stmt.?));
    const storage_value = zqlite.storage.Value{ .Real = value };

    statement.bindParameter(@intCast(index), storage_value) catch return ZQLITE_ERROR;
    return ZQLITE_OK;
}

/// Bind a null parameter
export fn zqlite_bind_null(stmt: ?*zqlite_stmt_t, index: c_int) c_int {
    if (stmt == null) return ZQLITE_MISUSE;

    const statement: *zqlite.db.PreparedStatement = @ptrCast(@alignCast(stmt.?));
    const storage_value = zqlite.storage.Value.Null;

    statement.bindParameter(@intCast(index), storage_value) catch return ZQLITE_ERROR;
    return ZQLITE_OK;
}

/// Execute a prepared statement
export fn zqlite_step(stmt: ?*zqlite_stmt_t) c_int {
    if (stmt == null) return ZQLITE_MISUSE;

    // TODO: Implement proper step execution
    return ZQLITE_OK;
}

/// Reset a prepared statement
export fn zqlite_reset(stmt: ?*zqlite_stmt_t) c_int {
    if (stmt == null) return ZQLITE_MISUSE;

    const statement: *zqlite.db.PreparedStatement = @ptrCast(@alignCast(stmt.?));
    statement.reset();
    return ZQLITE_OK;
}

/// Finalize a prepared statement
export fn zqlite_finalize(stmt: ?*zqlite_stmt_t) c_int {
    if (stmt) |s| {
        const statement: *zqlite.db.PreparedStatement = @ptrCast(@alignCast(s));
        statement.deinit();
    }
    return ZQLITE_OK;
}

/// Begin a transaction
export fn zqlite_begin_transaction(conn: ?*zqlite_connection_t) c_int {
    if (conn == null) return ZQLITE_MISUSE;

    const connection: *zqlite.db.Connection = @ptrCast(@alignCast(conn.?));
    connection.begin() catch return ZQLITE_ERROR;
    return ZQLITE_OK;
}

/// Commit a transaction
export fn zqlite_commit_transaction(conn: ?*zqlite_connection_t) c_int {
    if (conn == null) return ZQLITE_MISUSE;

    const connection: *zqlite.db.Connection = @ptrCast(@alignCast(conn.?));
    connection.commit() catch return ZQLITE_ERROR;
    return ZQLITE_OK;
}

/// Rollback a transaction
export fn zqlite_rollback_transaction(conn: ?*zqlite_connection_t) c_int {
    if (conn == null) return ZQLITE_MISUSE;

    const connection: *zqlite.db.Connection = @ptrCast(@alignCast(conn.?));
    connection.rollback() catch return ZQLITE_ERROR;
    return ZQLITE_OK;
}

/// Get the last error message
export fn zqlite_errmsg(conn: ?*zqlite_connection_t) [*:0]const u8 {
    _ = conn; // TODO: Implement error message tracking
    return "Unknown error";
}

/// Get the version string
export fn zqlite_version() [*:0]const u8 {
    return zqlite.version.VERSION_STRING.ptr;
}

/// Cleanup global resources
export fn zqlite_shutdown() void {
    _ = gpa.deinit();
}

// Test the C API
test "c api basic functionality" {
    const testing = std.testing;

    // Test opening database
    const conn = zqlite_open(":memory:");
    try testing.expect(conn != null);
    defer zqlite_close(conn);

    // Test executing statement
    const result = zqlite_execute(conn, "CREATE TABLE test (id INTEGER, name TEXT)");
    try testing.expectEqual(ZQLITE_OK, result);

    // Test version
    const version = zqlite_version();
    try testing.expect(std.mem.len(version) > 0);
}

test "c api prepared statements" {
    const testing = std.testing;

    // Test opening database
    const conn = zqlite_open(":memory:");
    try testing.expect(conn != null);
    defer zqlite_close(conn);

    // Create table
    _ = zqlite_execute(conn, "CREATE TABLE test (id INTEGER, name TEXT)");

    // Test prepared statement
    const stmt = zqlite_prepare(conn, "INSERT INTO test VALUES (?, ?)");
    try testing.expect(stmt != null);
    defer _ = zqlite_finalize(stmt);

    // Test binding parameters
    try testing.expectEqual(ZQLITE_OK, zqlite_bind_int(stmt, 0, 123));
    try testing.expectEqual(ZQLITE_OK, zqlite_bind_text(stmt, 1, "test"));
}
