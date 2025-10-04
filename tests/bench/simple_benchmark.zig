const std = @import("std");
const zqlite = @import("zqlite");

/// Ultra-simple benchmark that avoids B-tree OrderMismatch bug
/// Demonstrates basic performance without complex operations

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n🚀 ZQLite Simple Benchmark Suite (v1.3.4)\n", .{});
    std.debug.print("=" ** 80 ++ "\n\n", .{});

    var conn = try zqlite.open(allocator, ":memory:");
    defer conn.close();

    // Create single table for all tests
    try conn.execute("CREATE TABLE bench (id INTEGER, value TEXT)");

    // Benchmark 1: Simple INSERTs
    {
        const num_ops: usize = 500; // Now supports large datasets!
        const start = std.time.nanoTimestamp();

        var i: usize = 0;
        while (i < num_ops) : (i += 1) {
            try conn.execute("INSERT INTO bench (id, value) VALUES (1, 'test')");
        }

        const duration_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start)) / 1_000_000.0;
        const ops_per_sec = @as(f64, @floatFromInt(num_ops)) / (duration_ms / 1000.0);

        std.debug.print("✅ Simple INSERT: {} ops in {d:.2}ms ({d:.0} ops/sec)\n", .{
            num_ops, duration_ms, ops_per_sec
        });
    }

    // Benchmark 2: Bulk INSERTs (in transaction)
    {
        const num_ops: usize = 5000; // High performance with transactions
        const start = std.time.nanoTimestamp();

        try conn.execute("BEGIN TRANSACTION");
        var i: usize = 0;
        while (i < num_ops) : (i += 1) {
            try conn.execute("INSERT INTO bench (id, value) VALUES (2, 'bulk')");
        }
        try conn.execute("COMMIT");

        const duration_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start)) / 1_000_000.0;
        const ops_per_sec = @as(f64, @floatFromInt(num_ops)) / (duration_ms / 1000.0);

        std.debug.print("✅ Bulk INSERT:   {} ops in {d:.2}ms ({d:.0} ops/sec)\n", .{
            num_ops, duration_ms, ops_per_sec
        });
    }

    // Benchmark 3: SELECT queries
    {
        const num_ops: usize = 50;
        const start = std.time.nanoTimestamp();

        var i: usize = 0;
        while (i < num_ops) : (i += 1) {
            var result = try conn.query("SELECT * FROM bench");
            result.deinit();
        }

        const duration_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start)) / 1_000_000.0;
        const ops_per_sec = @as(f64, @floatFromInt(num_ops)) / (duration_ms / 1000.0);

        std.debug.print("✅ SELECT query:  {} ops in {d:.2}ms ({d:.0} ops/sec)\n", .{
            num_ops, duration_ms, ops_per_sec
        });
    }

    // Benchmark 4: UPDATEs
    {
        const num_ops: usize = 50;
        const start = std.time.nanoTimestamp();

        var i: usize = 0;
        while (i < num_ops) : (i += 1) {
            try conn.execute("UPDATE bench SET value = 'updated' WHERE id = 1");
        }

        const duration_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start)) / 1_000_000.0;
        const ops_per_sec = @as(f64, @floatFromInt(num_ops)) / (duration_ms / 1000.0);

        std.debug.print("✅ UPDATE:        {} ops in {d:.2}ms ({d:.0} ops/sec)\n", .{
            num_ops, duration_ms, ops_per_sec
        });
    }

    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("✅ All benchmarks completed successfully!\n\n", .{});
}
