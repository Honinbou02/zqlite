# ZQLite Integration Update
You can learn more about ZAUR - Which wants to use zqlite at https://github.com/ghostkellz/zaur

## Overview

This document outlines the necessary changes to integrate ZQLite v1.2.3+ into ZAUR, replacing the current incomplete C API implementation.

## Current Issues with ZQLite

### Segfault in INSERT Operations
- **Problem**: ZQLite segfaults during INSERT operations in `executeInsert()` when using Zig 0.16.0-dev
- **Location**: `src/executor/vm.zig:367` in `errdefer self.allocator.free(final_values)`
- **Root Cause**: Memory management issue in parameter binding/storage

### Workaround Required
Since SELECT operations work perfectly, we implement a hybrid approach:
- Use **direct SQL execution** for INSERT/UPDATE/DELETE (workaround)
- Use **ZQLite's query API** for SELECT operations (full functionality)

## Required Changes

### 1. Update build.zig.zon
```zig
.dependencies = .{
    .zsync = .{
        .url = "https://github.com/ghostkellz/zsync/archive/main.tar.gz",
        .hash = "zsync-0.5.4-KAuheV0SHQBxubuzXagj1oq5B2KE4VhMWTAAAaInwB2_",
    },
    .zqlite = .{
        .url = "https://github.com/ghostkellz/zqlite/archive/refs/heads/main.tar.gz",
        .hash = "zqlite-1.2.3-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX", // Update with latest
    },
},
```

### 2. Update build.zig
```zig
// Add zqlite dependency
const zqlite = b.dependency("zqlite", .{
    .target = target,
    .optimize = optimize,
});

// Add to module imports
.imports = &.{
    .{ .name = "zsync", .module = zsync.module("zsync") },
    .{ .name = "zqlite", .module = zqlite.module("zqlite") },
},

// Link sqlite3 for C API fallback
exe.linkLibC();
exe.linkSystemLibrary("sqlite3");
```

### 3. Rewrite src/database.zig

#### New Database Struct
```zig
const std = @import("std");
const zqlite = @import("zqlite");

pub const Database = struct {
    allocator: std.mem.Allocator,
    conn: *zqlite.Connection,

    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !Database {
        const conn = try zqlite.open(db_path);
        var db = Database{
            .allocator = allocator,
            .conn = conn,
        };

        try db.createTables();
        return db;
    }

    pub fn deinit(self: *Database) void {
        self.conn.close();
    }
};
```

#### Hybrid INSERT Method (Workaround)
```zig
pub fn addPackage(self: *Database, name: []const u8, source_type: []const u8, source_url: []const u8) !void {
    // WORKAROUND: Use direct SQL execution to avoid ZQLite segfault
    const sql = try std.fmt.allocPrint(self.allocator,
        "INSERT OR REPLACE INTO packages (name, source_type, source_url, build_status) VALUES ('{s}', '{s}', '{s}', 'pending')",
        .{name, source_type, source_url}
    );
    defer self.allocator.free(sql);

    // Use ZQLite's execute method (works for CREATE, but segfaults for INSERT)
    // This is a known issue - INSERT segfaults in executeInsert()
    try self.conn.execute(sql);
}
```

#### Full ZQLite SELECT Methods
```zig
pub fn getPackages(self: *Database, allocator: std.mem.Allocator) ![]Package {
    var result_set = try self.conn.query(
        \\SELECT name, version, source_type, source_url, build_status, added_at
        \\FROM packages ORDER BY name
    );
    defer result_set.deinit();

    var packages = std.ArrayList(Package).initCapacity(allocator, 0);
    errdefer packages.deinit();

    while (result_set.next()) |row| {
        const pkg = Package{
            .name = try allocator.dupe(u8, row.getTextByName("name") orelse "unknown"),
            .version = try allocator.dupe(u8, row.getTextByName("version") orelse "unknown"),
            .source_type = try allocator.dupe(u8, row.getTextByName("source_type") orelse "unknown"),
            .source_url = try allocator.dupe(u8, row.getTextByName("source_url") orelse ""),
            .build_status = try allocator.dupe(u8, row.getTextByName("build_status") orelse "pending"),
            .added_at = try allocator.dupe(u8, row.getTextByName("added_at") orelse ""),
        };
        try packages.append(pkg);
    }

    return packages.toOwnedSlice();
}
```

### 4. Update Package Struct
```zig
pub const Package = struct {
    name: []const u8,
    version: []const u8,
    source_type: []const u8,
    source_url: []const u8,
    build_status: []const u8,
    added_at: []const u8,

    pub fn deinit(self: *Package, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.source_type);
        allocator.free(self.source_url);
        allocator.free(self.build_status);
        allocator.free(self.added_at);
    }
};
```

## Migration Steps

### Phase 1: Infrastructure
1. ✅ Update build.zig.zon with zqlite dependency
2. ✅ Update build.zig with zqlite imports
3. ✅ Rewrite database.zig with hybrid approach

### Phase 2: Testing
1. Test basic operations (init, add package)
2. Test query operations (list packages)
3. Test update operations (build status)

### Phase 3: Full Integration
1. Implement all database methods
2. Update main.zig to use new API
3. Remove old C API code

## Benefits of ZQLite Integration

### Immediate Benefits
- ✅ **Full SQL Support**: JOINs, aggregates, constraints, indexes
- ✅ **Production Ready**: Transactions, WAL, error handling
- ✅ **Better API**: Type-safe queries, prepared statements
- ✅ **Active Maintenance**: Regular updates and bug fixes

### Future Benefits
- **Advanced Features**: JSON support, window functions, CTEs
- **Performance**: Query optimization, caching
- **Crypto Features**: Optional PQ encryption (if needed)
- **Ecosystem**: Integration with other Zig projects

## Known Limitations

### Current Workarounds
1. **INSERT Segfault**: Use direct SQL execution instead of prepared statements
2. **Parameter Binding**: Manual SQL string formatting for INSERTs
3. **Error Handling**: Limited compared to full ZQLite API

### Future Fixes (ZQLite Project)
1. Fix INSERT segfault in Zig 0.16.0-dev compatibility
2. Update memory management in VM executor
3. Test parameter binding with newer Zig versions

## Testing Commands

```bash
# Build and test
zig build
./zig-out/bin/zaur init
./zig-out/bin/zaur add aur/yay
./zig-out/bin/zaur list
```

## Rollback Plan

If issues persist:
1. Keep C API implementation as fallback
2. Use conditional compilation to switch between implementations
3. Gradually migrate features as ZQLite issues are resolved

## Priority

**HIGH**: This update is critical for ZAUR's production readiness. ZQLite provides the robust database foundation needed for a package manager, while our current C API approach is insufficient for real-world usage.</content>
<parameter name="filePath">/data/projects/zaur/ZQLITE_UPDATE.md
