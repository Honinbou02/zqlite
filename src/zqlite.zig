const std = @import("std");

// Version information
pub const version = @import("version.zig");

// New data structures for v1.2.5
pub const OpenOptions = struct {
    enable_async: bool = false,
    connection_pool_size: u32 = 4,
    enable_cache: bool = false,
    btree_cache_size: usize = 1000,
    plan_cache_size: usize = 100,
    enable_sqlite_compat: bool = false,
    enable_package_manager: bool = false,
    enable_error_reporting: bool = false,
    error_history_size: usize = 1000,
};

// Core database modules
pub const db = @import("db/connection.zig");
pub const Connection = db.Connection; // Export for convenience
pub const storage = @import("db/storage.zig");
pub const btree = @import("db/btree.zig");
pub const wal = @import("db/wal.zig");
pub const pager = @import("db/pager.zig");
pub const encryption = @import("db/encryption.zig");
pub const connection_pool = @import("db/connection_pool.zig");

// SQL parsing modules
pub const tokenizer = @import("parser/tokenizer.zig");
pub const ast = @import("parser/ast.zig");
pub const parser = @import("parser/parser.zig");

// Query execution modules
pub const planner = @import("executor/planner.zig");
pub const vm = @import("executor/vm.zig");
pub const prepared_statements = @import("executor/prepared_statements.zig");
pub const window_functions = @import("executor/window_functions.zig");

// CLI shell
pub const cli = @import("shell/cli.zig");

// Advanced cryptographic features (optional - v1.2.2)
pub const crypto = if (@import("builtin").is_test or @hasDecl(@import("root"), "zqlite_enable_crypto"))
    struct {
        pub const CryptoEngine = @import("crypto/secure_storage.zig").CryptoEngine;
        pub const CryptoTransactionLog = @import("crypto/secure_storage.zig").CryptoTransactionLog;
        pub const EncryptedField = struct {
            ciphertext: []u8,
            nonce: [12]u8,
            tag: [16]u8,

            pub fn deinit(self: *EncryptedField, allocator: std.mem.Allocator) void {
                allocator.free(self.ciphertext);
            }
        };
        pub const ZKProof = struct {
            proof_data: []u8,
            commitment: [32]u8,
            challenge: [32]u8,

            pub fn deinit(self: *ZKProof, allocator: std.mem.Allocator) void {
                allocator.free(self.proof_data);
            }
        };
        pub const HybridSignature = struct {
            classical: [64]u8, // Ed25519 signature
            post_quantum: []u8, // ML-DSA-65 signature

            pub fn deinit(self: *HybridSignature, allocator: std.mem.Allocator) void {
                allocator.free(self.post_quantum);
            }
        };
    }
else
    struct {
        // Crypto disabled - stub implementations
        pub const CryptoEngine = @TypeOf(null);
        pub const CryptoTransactionLog = @TypeOf(null);
        pub const EncryptedField = @TypeOf(null);
        pub const ZKProof = @TypeOf(null);
        pub const HybridSignature = @TypeOf(null);
    };

// Enhanced async database operations with zsync v0.5.4 features
pub const async_ops = @import("concurrent/async_operations.zig");

// SQLite compatibility layer
pub const sqlite_compat = @import("sqlite_compat/sqlite_compatibility.zig");

// Performance optimizations
pub const performance = @import("performance/cache_manager.zig");
pub const query_cache = @import("performance/query_cache.zig");

// Zeppelin package manager integration
pub const zeppelin = @import("zeppelin/package_manager.zig");

// Enhanced error reporting  
pub const error_handling = @import("error_handling/enhanced_errors.zig");
pub const database_errors = @import("error_handling/database_errors.zig");

// Post-quantum transport (optional - v1.2.2)
pub const transport = if (@import("builtin").is_test or @hasDecl(@import("root"), "zqlite_enable_transport"))
    struct {
        pub const Transport = @import("transport/transport.zig").Transport;
        pub const PQQuicTransport = @import("transport/pq_quic.zig").PQQuicTransport;
        pub const PQDatabaseTransport = @import("transport/pq_quic.zig").PQDatabaseTransport;
    }
else
    struct {
        // Transport disabled - stub implementations
        pub const Transport = @TypeOf(null);
        pub const PQQuicTransport = @TypeOf(null);
        pub const PQDatabaseTransport = @TypeOf(null);
    };

// Advanced indexing
pub const advanced_indexes = @import("indexing/advanced_indexes.zig");

// Version and metadata - now centralized in version.zig
pub const build_info = version.FULL_VERSION_STRING ++ " - PostgreSQL-compatible embedded database with enterprise features";

// Main API functions
pub fn open(allocator: std.mem.Allocator, path: []const u8) !*db.Connection {
    return db.Connection.open(allocator, path);
}

pub fn openMemory(allocator: std.mem.Allocator) !*db.Connection {
    return db.Connection.openMemory(allocator);
}

/// Create connection pool for high-concurrency applications
pub fn createConnectionPool(allocator: std.mem.Allocator, database_path: ?[]const u8, min_connections: u32, max_connections: u32) !*connection_pool.ConnectionPool {
    return connection_pool.ConnectionPool.init(allocator, database_path, min_connections, max_connections);
}

/// Create query cache for improved performance
pub fn createQueryCache(allocator: std.mem.Allocator, max_entries: usize, max_memory_bytes: usize) !*query_cache.QueryCache {
    return query_cache.QueryCache.init(allocator, max_entries, max_memory_bytes);
}

/// Generate UUID v4
pub fn generateUUID(random: std.Random) [16]u8 {
    return ast.UUIDUtils.generateV4(random);
}

/// Parse UUID from string
pub fn parseUUID(uuid_str: []const u8) ![16]u8 {
    return ast.UUIDUtils.parseFromString(uuid_str);
}

/// Convert UUID to string
pub fn uuidToString(uuid: [16]u8, allocator: std.mem.Allocator) ![]u8 {
    return ast.UUIDUtils.toString(uuid, allocator);
}

// Advanced print function for demo purposes
pub fn advancedPrint() !void {
    std.debug.print("🟦 {s}\n", .{build_info});
    std.debug.print("   PostgreSQL Features: JSON/JSONB, UUIDs, Arrays, Window Functions, CTEs\n", .{});
    std.debug.print("   Performance: Connection Pooling, Query Caching, Prepared Statements\n", .{});
    std.debug.print("   Enterprise: Enhanced Error Handling, Transaction Safety\n", .{});
    std.debug.print("   Status: Production Ready v1.3.0! 🚀\n", .{});
}

// Tests
test "zqlite version info" {
    try std.testing.expect(std.mem.eql(u8, version, "1.3.0"));
}

test "build info contains version" {
    try std.testing.expect(std.mem.indexOf(u8, build_info, version) != null);
}
