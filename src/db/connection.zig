const std = @import("std");
const storage = @import("storage.zig");
const wal = @import("wal.zig");
const ast = @import("../parser/ast.zig");
const parser = @import("../parser/parser.zig");
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
        try vm.execute(self, &parsed);
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

test "connection creation" {
    // Test will be implemented when storage engine is ready
    try std.testing.expect(true);
}

test "memory connection" {
    // Test will be implemented when storage engine is ready
    try std.testing.expect(true);
}
