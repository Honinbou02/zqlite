const std = @import("std");
const storage = @import("storage.zig");
const wal = @import("wal.zig");
const ast = @import("../parser/ast.zig");
const parser = @import("../parser/parser.zig");
const planner = @import("../executor/planner.zig");
const vm = @import("../executor/vm.zig");

/// Database connection handle
pub const Connection = struct {
    allocator: std.mem.Allocator,
    storage_engine: *storage.StorageEngine,
    wal: ?*wal.WriteAheadLog,
    is_memory: bool,
    path: ?[]const u8,

    const Self = @This();

    /// Open a database file
    pub fn open(path: []const u8) !*Self {
        var allocator = std.heap.page_allocator;

        var conn = try allocator.create(Self);
        conn.allocator = allocator;
        conn.storage_engine = try storage.StorageEngine.init(allocator, path);
        conn.wal = try wal.WriteAheadLog.init(allocator, path);
        conn.is_memory = false;
        conn.path = try allocator.dupe(u8, path);

        return conn;
    }

    /// Open an in-memory database
    pub fn openMemory() !*Self {
        var allocator = std.heap.page_allocator;

        var conn = try allocator.create(Self);
        conn.allocator = allocator;
        conn.storage_engine = try storage.StorageEngine.initMemory(allocator);
        conn.wal = null; // No WAL for in-memory databases
        conn.is_memory = true;
        conn.path = null;

        return conn;
    }

    /// Execute a SQL statement
    pub fn execute(self: *Self, sql: []const u8) !void {
        // Parse the SQL
        var parsed = try parser.parse(self.allocator, sql);
        defer parsed.deinit();

        // Execute via virtual machine
        try vm.execute(self, &parsed.statement);
    }

    /// Begin a transaction
    pub fn begin(self: *Self) !void {
        if (self.wal) |w| {
            try w.beginTransaction();
        }
    }

    /// Commit a transaction
    pub fn commit(self: *Self) !void {
        if (self.wal) |w| {
            try w.commit();
        }
    }

    /// Rollback a transaction
    pub fn rollback(self: *Self) !void {
        if (self.wal) |w| {
            try w.rollback();
        }
    }

    /// Prepare a SQL statement
    pub fn prepare(self: *Self, sql: []const u8) !*PreparedStatement {
        return PreparedStatement.prepare(self.allocator, self, sql);
    }

    /// Close the database connection
    pub fn close(self: *Self) void {
        if (self.wal) |w| {
            w.deinit();
        }
        self.storage_engine.deinit();
        if (self.path) |p| {
            self.allocator.free(p);
        }
        self.allocator.destroy(self);
    }

    /// Get database info
    pub fn info(self: *Self) ConnectionInfo {
        return ConnectionInfo{
            .is_memory = self.is_memory,
            .path = self.path,
            .has_wal = self.wal != null,
        };
    }
};

pub const ConnectionInfo = struct {
    is_memory: bool,
    path: ?[]const u8,
    has_wal: bool,
};

/// Prepared statement for optimized execution
pub const PreparedStatement = struct {
    allocator: std.mem.Allocator,
    sql: []const u8,
    parsed_statement: ast.Statement,
    execution_plan: planner.ExecutionPlan,
    parameter_count: u32,
    parameters: []storage.Value,

    const Self = @This();

    /// Prepare a SQL statement
    pub fn prepare(allocator: std.mem.Allocator, connection: *Connection, sql: []const u8) !*Self {
        _ = connection; // Will be used for validation in the future
        var stmt = try allocator.create(Self);
        stmt.allocator = allocator;
        stmt.sql = try allocator.dupe(u8, sql);

        // Parse the SQL
        var parsed_result = try parser.parse(allocator, sql);
        stmt.parsed_statement = parsed_result.statement;
        parsed_result.parser.deinit(); // Clean up parser resources

        // Create execution plan
        var query_planner = planner.Planner.init(allocator);
        stmt.execution_plan = try query_planner.plan(&stmt.parsed_statement);

        // Count parameters (? placeholders)
        stmt.parameter_count = countParameters(sql);
        stmt.parameters = try allocator.alloc(storage.Value, stmt.parameter_count);

        // Initialize parameters to NULL
        for (stmt.parameters) |*param| {
            param.* = storage.Value.Null;
        }

        return stmt;
    }

    /// Bind a parameter value
    pub fn bindParameter(self: *Self, index: u32, value: storage.Value) !void {
        if (index >= self.parameter_count) {
            return error.InvalidParameterIndex;
        }

        // Clean up old value
        self.parameters[index].deinit(self.allocator);

        // Clone the new value
        self.parameters[index] = try cloneValue(self.allocator, value);
    }

    /// Execute the prepared statement
    pub fn execute(self: *Self, connection: *Connection) !vm.ExecutionResult {
        var virtual_machine = vm.VirtualMachine.init(connection.allocator, connection);
        return virtual_machine.execute(&self.execution_plan);
    }

    /// Reset parameters
    pub fn reset(self: *Self) void {
        for (self.parameters) |*param| {
            param.deinit(self.allocator);
            param.* = storage.Value.Null;
        }
    }

    /// Clean up prepared statement
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.sql);
        self.parsed_statement.deinit(self.allocator);
        self.execution_plan.deinit();

        for (self.parameters) |param| {
            param.deinit(self.allocator);
        }
        self.allocator.free(self.parameters);

        self.allocator.destroy(self);
    }

    /// Count ? placeholders in SQL
    fn countParameters(sql: []const u8) u32 {
        var count: u32 = 0;
        for (sql) |char| {
            if (char == '?') {
                count += 1;
            }
        }
        return count;
    }

    /// Clone a storage value
    fn cloneValue(allocator: std.mem.Allocator, value: storage.Value) !storage.Value {
        return switch (value) {
            .Integer => |i| storage.Value{ .Integer = i },
            .Real => |r| storage.Value{ .Real = r },
            .Text => |t| storage.Value{ .Text = try allocator.dupe(u8, t) },
            .Blob => |b| storage.Value{ .Blob = try allocator.dupe(u8, b) },
            .Null => storage.Value.Null,
        };
    }
};

test "connection creation" {
    // Test will be implemented when storage engine is ready
    try std.testing.expect(true);
}

test "memory connection" {
    // Test will be implemented when storage engine is ready
    try std.testing.expect(true);
}
