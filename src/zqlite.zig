const std = @import("std");

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

// SQL parsing modules
pub const tokenizer = @import("parser/tokenizer.zig");
pub const ast = @import("parser/ast.zig");
pub const parser = @import("parser/parser.zig");

// Query execution modules
pub const planner = @import("executor/planner.zig");
pub const vm = @import("executor/vm.zig");

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

// Zeppelin package manager integration
pub const zeppelin = @import("zeppelin/package_manager.zig");

// Enhanced error reporting
pub const error_handling = @import("error_handling/enhanced_errors.zig");

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

// Version and metadata
pub const version = "1.2.5";
pub const build_info = "zqlite " ++ version ++ " - Universal embedded database with optional crypto features";

// Main API functions
pub fn open(path: []const u8) !*db.Connection {
    return db.Connection.open(path);
}

pub fn openMemory() !*db.Connection {
    return db.Connection.openMemory();
}

// Advanced print function for demo purposes
pub fn advancedPrint() !void {
    std.debug.print("🟦 {s}\n", .{build_info});
    std.debug.print("   Features: B-tree storage, WAL, SQL parsing\n", .{});
    std.debug.print("   Status: Building core functionality...\n", .{});
}

// Tests
test "zqlite version info" {
    try std.testing.expect(std.mem.eql(u8, version, "1.2.5"));
}

test "build info contains version" {
    try std.testing.expect(std.mem.indexOf(u8, build_info, version) != null);
}
