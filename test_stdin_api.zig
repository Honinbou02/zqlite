const std = @import("std");

pub fn main() !void {
    // Try the file-based approach
    const stdin = std.fs.stdin;
    _ = stdin;
}