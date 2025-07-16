const std = @import("std");
const zsync = @import("zsync");
const storage = @import("../db/storage.zig");
const connection = @import("../db/connection.zig");

/// Async database operations for high-performance concurrent access
/// Perfect for AI agents, VPN servers, and real-time applications
pub const AsyncDatabase = struct {
    allocator: std.mem.Allocator,
    connection_pool: ConnectionPool,
    io: zsync.ThreadPoolIo,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, db_path: []const u8, pool_size: u32) !Self {
        const connection_pool = try ConnectionPool.init(allocator, db_path, pool_size);

        return Self{
            .allocator = allocator,
            .connection_pool = connection_pool,
            .io = zsync.ThreadPoolIo{},
        };
    }

    /// Execute SQL asynchronously (production-ready for AI agents)
    pub fn executeAsync(self: *Self, sql: []const u8) !QueryResult {
        var future = self.io.async(executeSqlWorker, .{ self, sql });
        defer future.cancel(self.io) catch {};
        
        return try future.await(self.io);
    }

    /// Batch execute multiple queries (production-ready for AI agents)
    pub fn batchExecuteAsync(self: *Self, queries: [][]const u8) ![]QueryResult {
        var future = self.io.async(batchExecuteWorker, .{ self, queries });
        defer future.cancel(self.io) catch {};
        
        return try future.await(self.io);
    }

    /// Transaction processing (production-ready for VPN logging)
    pub fn transactionAsync(self: *Self, queries: [][]const u8) !QueryResult {
        var future = self.io.async(transactionWorker, .{ self, queries });
        defer future.cancel(self.io) catch {};
        
        return try future.await(self.io);
    }

    fn executeSqlWorker(self: *AsyncDatabase, sql: []const u8) !QueryResult {
        defer zsync.yieldNow();
        
        const conn = try self.connection_pool.acquire();
        defer self.connection_pool.release(conn);
        
        // Parse and execute SQL
        const parser = @import("../parser/parser.zig");
        const vm = @import("../executor/vm.zig");
        
        var parsed = parser.parse(self.allocator, sql) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Parse error: {}", .{err});
            return QueryResult{
                .rows = &[_]storage.Row{},
                .affected_rows = 0,
                .success = false,
                .error_message = error_msg,
            };
        };
        defer parsed.deinit(self.allocator);
        
        var virtual_machine = vm.VirtualMachine.init(self.allocator, conn);
        var planner = @import("../executor/planner.zig").Planner.init(self.allocator);
        
        var plan = planner.plan(&parsed) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Planning error: {}", .{err});
            return QueryResult{
                .rows = &[_]storage.Row{},
                .affected_rows = 0,
                .success = false,
                .error_message = error_msg,
            };
        };
        defer plan.deinit();
        
        var result = virtual_machine.execute(&plan) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Execution error: {}", .{err});
            return QueryResult{
                .rows = &[_]storage.Row{},
                .affected_rows = 0,
                .success = false,
                .error_message = error_msg,
            };
        };
        
        // Convert ExecutionResult to QueryResult
        var rows = try self.allocator.alloc(storage.Row, result.rows.items.len);
        for (result.rows.items, 0..) |src_row, i| {
            // Clone the row values
            var values = try self.allocator.alloc(storage.Value, src_row.values.len);
            for (src_row.values, 0..) |value, j| {
                values[j] = try cloneValue(self.allocator, value);
            }
            rows[i] = storage.Row{ .values = values };
        }
        
        result.deinit(self.allocator);
        
        return QueryResult{
            .rows = rows,
            .affected_rows = result.affected_rows,
            .success = true,
            .error_message = null,
        };
    }
    
    fn cloneValue(allocator: std.mem.Allocator, value: storage.Value) !storage.Value {
        return switch (value) {
            .Integer => |i| storage.Value{ .Integer = i },
            .Real => |r| storage.Value{ .Real = r },
            .Text => |t| storage.Value{ .Text = try allocator.dupe(u8, t) },
            .Blob => |b| storage.Value{ .Blob = try allocator.dupe(u8, b) },
            .Null => storage.Value.Null,
            .Parameter => |p| storage.Value{ .Parameter = p },
        };
    }

    fn batchExecuteWorker(self: *AsyncDatabase, queries: [][]const u8) ![]QueryResult {
        defer zsync.yieldNow();
        
        var results = try self.allocator.alloc(QueryResult, queries.len);
        
        for (queries, 0..) |query, i| {
            results[i] = try self.executeSqlWorker(query);
            
            // Yield every 10 queries to allow other tasks
            if (i % 10 == 0) {
                zsync.yieldNow();
            }
        }
        
        return results;
    }

    fn transactionWorker(self: *AsyncDatabase, queries: [][]const u8) !QueryResult {
        defer zsync.yieldNow();
        
        const conn = try self.connection_pool.acquire();
        defer self.connection_pool.release(conn);
        
        // Begin transaction
        try conn.beginTransaction();
        
        var total_affected: u32 = 0;
        errdefer conn.rollbackTransaction() catch {};
        
        // Execute all queries in transaction
        for (queries) |query| {
            const result = try self.executeSqlWorker(query);
            defer result.deinit(self.allocator);
            
            if (!result.success) {
                try conn.rollbackTransaction();
                return QueryResult{
                    .rows = &[_]storage.Row{},
                    .affected_rows = 0,
                    .success = false,
                    .error_message = result.error_message,
                };
            }
            
            total_affected += result.affected_rows;
        }
        
        // Commit transaction
        try conn.commitTransaction();
        
        return QueryResult{
            .rows = &[_]storage.Row{},
            .affected_rows = total_affected,
            .success = true,
            .error_message = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.connection_pool.deinit();
    }
};

/// Connection pool for managing database connections
const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    connections: std.ArrayList(*connection.Connection),
    available: std.Thread.Semaphore,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, db_path: []const u8, pool_size: u32) !Self {
        var connections = std.ArrayList(*connection.Connection).init(allocator);

        // Create connections
        for (0..pool_size) |_| {
            const conn = try connection.Connection.open(db_path);
            try connections.append(conn);
        }

        return Self{
            .allocator = allocator,
            .connections = connections,
            .available = std.Thread.Semaphore{ .permits = pool_size },
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn acquire(self: *Self) !*connection.Connection {
        self.available.wait();
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return self.connections.pop();
    }

    pub fn release(self: *Self, conn: *connection.Connection) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.connections.append(conn) catch {};
        self.available.post();
    }

    pub fn deinit(self: *Self) void {
        for (self.connections.items) |conn| {
            conn.close();
        }
        self.connections.deinit();
    }
};

/// Production-ready query result type
pub const QueryResult = struct {
    rows: []storage.Row,
    affected_rows: u64,
    success: bool,
    error_message: ?[]const u8,

    pub fn deinit(self: *QueryResult, allocator: std.mem.Allocator) void {
        for (self.rows) |row| {
            for (row.values) |value| {
                switch (value) {
                    .Text => |t| allocator.free(t),
                    .Blob => |b| allocator.free(b),
                    else => {},
                }
            }
            allocator.free(row.values);
        }
        if (self.rows.len > 0) {
            allocator.free(self.rows);
        }
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// AI Agent Database - High-performance encrypted database for AI applications
pub const AIAgentDatabase = struct {
    async_db: *AsyncDatabase,
    crypto: *@import("secure_storage.zig").CryptoEngine,

    const Self = @This();

    pub fn init(async_db: *AsyncDatabase, crypto: *@import("secure_storage.zig").CryptoEngine) Self {
        return Self{
            .async_db = async_db,
            .crypto = crypto,
        };
    }

    /// Store encrypted AI agent credentials
    pub fn storeAgentCredentials(self: *Self, agent_id: []const u8, credentials: []const u8) !void {
        const encrypted = try self.crypto.encrypt(credentials);
        defer self.crypto.allocator.free(encrypted);
        
        const sql = try std.fmt.allocPrint(self.async_db.allocator, 
            "INSERT INTO agent_credentials (agent_id, encrypted_data) VALUES ('{}', '{}')", 
            .{ agent_id, std.fmt.fmtSliceHexLower(encrypted) });
        defer self.async_db.allocator.free(sql);
        
        _ = try self.async_db.executeAsync(sql);
    }

    /// Retrieve and decrypt AI agent credentials
    pub fn getAgentCredentials(self: *Self, agent_id: []const u8) ![]u8 {
        const sql = try std.fmt.allocPrint(self.async_db.allocator, 
            "SELECT encrypted_data FROM agent_credentials WHERE agent_id = '{}'", 
            .{agent_id});
        defer self.async_db.allocator.free(sql);
        
        const result = try self.async_db.executeAsync(sql);
        defer result.deinit(self.async_db.allocator);
        
        if (!result.success) {
            return error.QueryFailed;
        }
        
        if (result.rows.len == 0) {
            return error.AgentNotFound;
        }
        
        // Get encrypted data from first row, first column
        const encrypted_data = switch (result.rows[0].values[0]) {
            .Text => |t| t,
            .Blob => |b| b,
            else => return error.InvalidData,
        };
        
        // Decrypt the data
        return try self.crypto.decrypt(encrypted_data);
    }
};