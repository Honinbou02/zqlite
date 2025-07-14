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
    pub fn beginTransaction(self: *Self) !void {
        if (self.wal) |w| {
            try w.beginTransaction();
        }
    }
    
    /// Begin a transaction (alias)
    pub fn begin(self: *Self) !void {
        try self.beginTransaction();
    }

    /// Commit a transaction
    pub fn commitTransaction(self: *Self) !void {
        if (self.wal) |w| {
            try w.commit();
        }
    }
    
    /// Commit a transaction (alias)
    pub fn commit(self: *Self) !void {
        try self.commitTransaction();
    }

    /// Rollback a transaction
    pub fn rollbackTransaction(self: *Self) !void {
        if (self.wal) |w| {
            try w.rollback();
        }
    }
    
    /// Rollback a transaction (alias)
    pub fn rollback(self: *Self) !void {
        try self.rollbackTransaction();
    }

    /// Execute a function within a transaction with automatic rollback on error
    pub fn transaction(self: *Self, comptime context_type: type, function: *const fn (self: *Self, context: context_type) anyerror!void, context: context_type) !void {
        try self.begin();
        errdefer self.rollback() catch |err| {
            std.log.err("Failed to rollback transaction: {}", .{err});
        };
        
        try function(self, context);
        try self.commit();
    }

    /// Execute a function within a transaction (no context parameter)
    pub fn transactionSimple(self: *Self, function: *const fn (self: *Self) anyerror!void) !void {
        try self.begin();
        errdefer self.rollback() catch |err| {
            std.log.err("Failed to rollback transaction: {}", .{err});
        };
        
        try function(self);
        try self.commit();
    }

    /// Execute multiple SQL statements within a transaction
    pub fn transactionExec(self: *Self, sql_statements: []const []const u8) !void {
        try self.begin();
        errdefer self.rollback() catch |err| {
            std.log.err("Failed to rollback transaction: {}", .{err});
        };
        
        for (sql_statements) |sql| {
            try self.execute(sql);
        }
        
        try self.commit();
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

    /// Simplified parameter binding with auto-type detection
    pub fn bind(self: *Self, index: u32, value: anytype) !void {
        const value_type = @TypeOf(value);
        const storage_value = switch (value_type) {
            i8, i16, i32, i64, u8, u16, u32 => storage.Value{ .Integer = @intCast(value) },
            comptime_int => storage.Value{ .Integer = value },
            f32, f64 => storage.Value{ .Real = @floatCast(value) },
            comptime_float => storage.Value{ .Real = value },
            []const u8 => storage.Value{ .Text = value },
            *const [5:0]u8, *const [4:0]u8, *const [3:0]u8, *const [6:0]u8, *const [7:0]u8, *const [8:0]u8, *const [9:0]u8, *const [10:0]u8, *const [11:0]u8, *const [12:0]u8, *const [13:0]u8, *const [14:0]u8, *const [15:0]u8, *const [16:0]u8, *const [17:0]u8, *const [18:0]u8, *const [19:0]u8, *const [20:0]u8 => storage.Value{ .Text = value },
            else => @compileError("Unsupported type for bind: " ++ @typeName(value_type) ++ " - use bindParameter() instead"),
        };
        
        try self.bindParameter(index, storage_value);
    }

    /// Bind NULL value
    pub fn bindNull(self: *Self, index: u32) !void {
        try self.bindParameter(index, storage.Value.Null);
    }

    /// Bind named parameter (future enhancement - for now just use positional)
    pub fn bindNamed(self: *Self, name: []const u8, value: anytype) !void {
        // For now, this is a placeholder. Named parameters would require
        // tracking parameter names during SQL parsing
        _ = self;
        _ = name;
        _ = value;
        return error.NamedParametersNotSupported;
    }

    /// Execute the prepared statement
    pub fn execute(self: *Self, connection: *Connection) !vm.ExecutionResult {
        var virtual_machine = vm.VirtualMachine.init(connection.allocator, connection);
        return virtual_machine.executeWithParameters(&self.execution_plan, self.parameters);
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
            .Parameter => |param_index| storage.Value{ .Parameter = param_index },
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
