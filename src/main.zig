const std = @import("std");
const zqlite = @import("zqlite");

pub fn main() !void {
    std.debug.print("🚀 Starting zqlite...\n", .{});
    try zqlite.advancedPrint();
    
    // Demo basic functionality
    std.debug.print("\n📋 Testing core modules:\n", .{});
    std.debug.print("   ✅ Library loaded successfully\n", .{});
    std.debug.print("   ✅ Version: {s}\n", .{zqlite.version});
    
    std.debug.print("\n🔧 Next steps:\n", .{});
    std.debug.print("   - Implement B-tree storage engine\n", .{});
    std.debug.print("   - Add SQL parser\n", .{});
    std.debug.print("   - Create WAL system\n", .{});
    std.debug.print("   - Build query executor\n", .{});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
