const std = @import("std");
const btree = @import("btree.zig");
const pager = @import("pager.zig");

/// Storage engine that manages tables and data persistence
pub const StorageEngine = struct {
    allocator: std.mem.Allocator,
    pager: *pager.Pager,
    tables: std.StringHashMap(*Table),
    indexes: std.StringHashMap(*Index),
    is_memory: bool,

    const Self = @This();

    /// Initialize storage engine with file backing
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !*Self {
        var engine = try allocator.create(Self);
        engine.allocator = allocator;
        engine.pager = try pager.Pager.init(allocator, path);
        engine.tables = std.StringHashMap(*Table).init(allocator);
        engine.indexes = std.StringHashMap(*Index).init(allocator);
        engine.is_memory = false;

        // Load existing tables from file
        try engine.loadTables();

        return engine;
    }

    /// Initialize in-memory storage engine
    pub fn initMemory(allocator: std.mem.Allocator) !*Self {
        var engine = try allocator.create(Self);
        engine.allocator = allocator;
        engine.pager = try pager.Pager.initMemory(allocator);
        engine.tables = std.StringHashMap(*Table).init(allocator);
        engine.indexes = std.StringHashMap(*Index).init(allocator);
        engine.is_memory = true;

        return engine;
    }

    /// Create a new table
    pub fn createTable(self: *Self, name: []const u8, schema: TableSchema) !void {
        const table = try Table.create(self.allocator, self.pager, name, schema);
        try self.tables.put(try self.allocator.dupe(u8, name), table);

        // Persist table metadata if not in-memory
        if (!self.is_memory) {
            try self.saveTableMetadata(table);
        }
    }

    /// Get a table by name
    pub fn getTable(self: *Self, name: []const u8) ?*Table {
        return self.tables.get(name);
    }

    /// Drop a table
    pub fn dropTable(self: *Self, name: []const u8) !void {
        if (self.tables.fetchRemove(name)) |entry| {
            entry.value.deinit();
            self.allocator.free(entry.key);
        }
    }

    /// Create an index
    pub fn createIndex(self: *Self, name: []const u8, table_name: []const u8, column_names: [][]const u8, is_unique: bool) !void {
        const index = try Index.create(self.allocator, self.pager, name, table_name, column_names, is_unique);
        try self.indexes.put(try self.allocator.dupe(u8, name), index);
    }

    /// Get an index by name
    pub fn getIndex(self: *Self, name: []const u8) ?*Index {
        return self.indexes.get(name);
    }

    /// Drop an index
    pub fn dropIndex(self: *Self, name: []const u8) !void {
        if (self.indexes.fetchRemove(name)) |entry| {
            entry.value.deinit(self.allocator);
            self.allocator.free(entry.key);
        }
    }

    /// Load existing tables from storage
    fn loadTables(self: *Self) !void {
        // This would read table metadata from page 0 or a dedicated metadata area
        // For now, this is a placeholder
        _ = self;
    }

    /// Save table metadata to storage
    fn saveTableMetadata(self: *Self, table: *Table) !void {
        // This would write table schema to a metadata page
        _ = self;
        _ = table;
    }

    /// Clean up storage engine
    pub fn deinit(self: *Self) void {
        var table_iterator = self.tables.iterator();
        while (table_iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.tables.deinit();

        var index_iterator = self.indexes.iterator();
        while (index_iterator.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.indexes.deinit();

        self.pager.deinit();
        self.allocator.destroy(self);
    }

    /// Get storage statistics
    pub fn getStats(self: *Self) StorageStats {
        const cache_stats = self.pager.getCacheStats();
        return StorageStats{
            .table_count = @intCast(self.tables.count()),
            .index_count = @intCast(self.indexes.count()),
            .is_memory = self.is_memory,
            .page_count = self.pager.getPageCount(),
            .cache_hit_ratio = cache_stats.hit_ratio,
            .cached_pages = cache_stats.cached_pages,
        };
    }
};

/// Table representation
pub const Table = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    schema: TableSchema,
    btree: *btree.BTree,
    row_count: u64,

    const Self = @This();

    /// Create a new table
    pub fn create(allocator: std.mem.Allocator, page_manager: *pager.Pager, name: []const u8, schema: TableSchema) !*Self {
        var table = try allocator.create(Self);
        table.allocator = allocator;
        table.name = try allocator.dupe(u8, name);
        table.schema = schema;
        table.btree = try btree.BTree.init(allocator, page_manager);
        table.row_count = 0;

        return table;
    }

    /// Insert a row into the table
    pub fn insert(self: *Self, row: Row) !void {
        try self.btree.insert(self.row_count, row);
        self.row_count += 1;
    }

    /// Select rows from the table
    pub fn select(self: *Self, allocator: std.mem.Allocator) ![]Row {
        return self.btree.selectAll(allocator);
    }

    /// Clean up table
    pub fn deinit(self: *Self) void {
        self.btree.deinit();
        self.allocator.free(self.name);
        self.schema.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

/// Table schema definition
pub const TableSchema = struct {
    columns: []Column,

    pub fn deinit(self: *TableSchema, allocator: std.mem.Allocator) void {
        for (self.columns) |column| {
            allocator.free(column.name);
        }
        allocator.free(self.columns);
    }
};

/// Column definition
pub const Column = struct {
    name: []const u8,
    data_type: DataType,
    is_primary_key: bool,
    is_nullable: bool,
};

/// Supported data types
pub const DataType = enum {
    Integer,
    Text,
    Real,
    Blob,
};

/// Row data
pub const Row = struct {
    values: []Value,

    pub fn deinit(self: *Row, allocator: std.mem.Allocator) void {
        for (self.values) |value| {
            value.deinit(allocator);
        }
        allocator.free(self.values);
    }
};

/// Value types
pub const Value = union(enum) {
    Integer: i64,
    Text: []const u8,
    Real: f64,
    Blob: []const u8,
    Null,

    pub fn deinit(self: Value, allocator: std.mem.Allocator) void {
        switch (self) {
            .Text => |text| allocator.free(text),
            .Blob => |blob| allocator.free(blob),
            else => {},
        }
    }
};

/// Storage statistics
pub const StorageStats = struct {
    table_count: u32,
    index_count: u32,
    is_memory: bool,
    page_count: u32,
    cache_hit_ratio: f64,
    cached_pages: u32,
};

/// Index definition
pub const Index = struct {
    name: []const u8,
    table_name: []const u8,
    column_names: [][]const u8,
    btree: *btree.BTree,
    is_unique: bool,

    const Self = @This();

    /// Create a new index
    pub fn create(allocator: std.mem.Allocator, page_manager: *pager.Pager, name: []const u8, table_name: []const u8, column_names: [][]const u8, is_unique: bool) !*Self {
        var index = try allocator.create(Self);
        index.name = try allocator.dupe(u8, name);
        index.table_name = try allocator.dupe(u8, table_name);

        // Clone column names
        index.column_names = try allocator.alloc([]const u8, column_names.len);
        for (column_names, 0..) |col_name, i| {
            index.column_names[i] = try allocator.dupe(u8, col_name);
        }

        index.btree = try btree.BTree.init(allocator, page_manager);
        index.is_unique = is_unique;

        return index;
    }

    /// Insert a key into the index
    pub fn insert(self: *Self, key: u64, row_id: u64) !void {
        if (self.is_unique) {
            // Check if key already exists
            if (try self.btree.search(key)) |_| {
                return error.UniqueConstraintViolation;
            }
        }

        // Create a row with just the row ID
        const index_row = Row{
            .values = try self.btree.allocator.alloc(Value, 1),
        };
        index_row.values[0] = Value{ .Integer = @intCast(row_id) };

        try self.btree.insert(key, index_row);
    }

    /// Search for a key in the index
    pub fn search(self: *Self, key: u64) !?u64 {
        if (try self.btree.search(key)) |row| {
            if (row.values.len > 0) {
                switch (row.values[0]) {
                    .Integer => |row_id| return @intCast(row_id),
                    else => return null,
                }
            }
        }
        return null;
    }

    /// Clean up index
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.table_name);
        for (self.column_names) |col_name| {
            allocator.free(col_name);
        }
        allocator.free(self.column_names);
        self.btree.deinit();
        allocator.destroy(self);
    }
};

test "storage engine creation" {
    try std.testing.expect(true); // Placeholder
}

test "table operations" {
    try std.testing.expect(true); // Placeholder
}
