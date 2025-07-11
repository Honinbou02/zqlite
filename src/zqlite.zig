const std = @import("std");

// Core database modules
pub const db = @import("db/connection.zig");
pub const Connection = db.Connection;  // Export for convenience
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

// Advanced cryptographic features (optional)
pub const crypto = struct {
    pub const CryptoEngine = @import("crypto/secure_storage.zig").CryptoEngine;
    pub const CryptoTransactionLog = @import("crypto/secure_storage.zig").CryptoTransactionLog;
    pub const CryptoInterface = @import("crypto/interface.zig").CryptoInterface;
    pub const CryptoConfig = @import("crypto/interface.zig").CryptoConfig;
    pub const CryptoBackend = @import("crypto/interface.zig").CryptoBackend;
    pub const HashVerifier = @import("crypto/hash_verification.zig").HashVerifier;
    pub const StabilityMonitor = @import("crypto/hash_verification.zig").StabilityMonitor;
    pub const ZKProof = @import("crypto/secure_storage.zig").ZKProof;
    pub const HybridSignature = @import("crypto/secure_storage.zig").HybridSignature;
    pub const EncryptedField = struct {
        ciphertext: []u8,
        nonce: [12]u8,
        tag: [16]u8,

        pub fn deinit(self: *EncryptedField, allocator: std.mem.Allocator) void {
            allocator.free(self.ciphertext);
        }
    };
};

// Async database operations
pub const async_ops = @import("concurrent/async_operations.zig");

// Post-quantum transport (optional)
pub const transport = struct {
    pub const Transport = @import("transport/transport.zig").Transport;
};

// Advanced indexing
pub const advanced_indexes = @import("indexing/advanced_indexes.zig");

// ZNS Integration (NEW in v0.8.0)
pub const zns_adapter = @import("crypto/zns_adapter.zig");

// Version and metadata
pub const version = "0.8.0";
pub const build_info = "zqlite " ++ version ++ " - Next-generation cryptographic database";

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
    try std.testing.expect(std.mem.eql(u8, version, "0.1.0"));
}

test "build info contains version" {
    try std.testing.expect(std.mem.indexOf(u8, build_info, version) != null);
}
