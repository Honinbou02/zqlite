const std = @import("std"); pub fn main() \!void { var buf: [100]u8 = undefined; const result = try std.io.getStdIn().reader().read(&buf); _ = result; }
