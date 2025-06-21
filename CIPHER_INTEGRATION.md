# Cipher DNS Integration Guide

## Adding zqlite to your Cipher DNS project

### 1. Add zqlite as a dependency

In your `build.zig.zon`:
```zig
.dependencies = .{
    .zqlite = .{
        .url = "https://github.com/ghostkellz/zqlite/archive/main.tar.gz",
        .hash = "...", // zig will fill this in
    },
},
```

In your `build.zig`:
```zig
const zqlite_dep = b.dependency("zqlite", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zqlite", zqlite_dep.module("zqlite"));
```

### 2. Basic Integration

```zig
const std = @import("std");
const zqlite = @import("zqlite");

pub const CipherDNS = struct {
    db: *zqlite.db.Connection,
    
    pub fn init(db_path: []const u8) !CipherDNS {
        const db = try zqlite.open(db_path);
        
        // Setup DNS schema
        try db.execute(
            \\CREATE TABLE records (
            \\  domain TEXT,
            \\  type TEXT,
            \\  value TEXT,
            \\  ttl INTEGER
            \\)
        );
        
        return CipherDNS{ .db = db };
    }
    
    pub fn query(self: *CipherDNS, domain: []const u8, qtype: []const u8) ![]DNSRecord {
        var buf: [256]u8 = undefined;
        const sql = try std.fmt.bufPrint(buf[0..], 
            "SELECT value, ttl FROM records WHERE domain = '{s}' AND type = '{s}'",
            .{ domain, qtype }
        );
        
        try self.db.execute(sql);
        // Parse results and return DNS records
        return &[_]DNSRecord{};
    }
    
    pub fn deinit(self: *CipherDNS) void {
        self.db.close();
    }
};

const DNSRecord = struct {
    domain: []const u8,
    rtype: []const u8,
    value: []const u8,
    ttl: u32,
};
```

### 3. Integration with zigDNS

Your Cipher server can combine:
- **zigDNS** for recursive resolution
- **zqlite** for authoritative data storage

```zig
pub fn handleDNSQuery(query: DNSQuery) !DNSResponse {
    // Check if we're authoritative for this domain
    if (cipher.isAuthoritative(query.domain)) {
        // Use zqlite for authoritative lookup
        return try cipher.authoritativeLookup(query);
    } else {
        // Use zigDNS for recursive resolution
        return try zigdns.resolve(query);
    }
}
```

### 4. Performance Features

- **In-memory mode**: `zqlite.openMemory()` for ultra-fast lookups
- **File-based**: `zqlite.open("dns.db")` for persistent storage
- **Transactions**: Use `db.begin()`, `db.commit()` for bulk updates
- **WAL mode**: Automatic write-ahead logging for durability

### 5. Production Deployment

```bash
# Copy zqlite to your server
cp zig-out/bin/zqlite /usr/local/bin/

# Initialize your DNS database
zqlite exec dns.db "CREATE TABLE records (domain TEXT, type TEXT, value TEXT, ttl INTEGER)"

# Import existing zone files (you can write a script for this)
zqlite exec dns.db "INSERT INTO records VALUES ('example.com', 'A', '192.168.1.10', 300)"
```

### 6. What You Can Remove/Simplify

Since you have zqlite working now, you can:

- ✅ **Remove complex backend dependencies** - No PostgreSQL, MySQL, etc.
- ✅ **Simplify deployment** - Single binary + database file
- ✅ **Remove ORM layers** - Direct SQL is fast and simple
- ✅ **Reduce memory usage** - Embedded database, no separate server
- ✅ **Faster startup** - No network connections to external databases

This makes Cipher a true "all-in-one" DNS solution that's easier to deploy and manage than traditional PowerDNS setups.
