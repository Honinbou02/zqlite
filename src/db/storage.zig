const std = @import("std");
const btree = @import("btree.zig");
const pager = @import("pager.zig");

/// Storage engine that manages tables and data persistence
pub const StorageEngine = struct {
    allocator: std.mem.Allocator,
    pager: *pager.Pager,
    tables: std.StringHashMap(*Table),
    is_memory: bool,

    const Self = @This();

    /// Initialize storage engine with file backing
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !*Self {
        var engine = try allocator.create(Self);
        engine.allocator = allocator;
        engine.pager = try pager.Pager.init(allocator, path);
        engine.tables = std.StringHashMap(*Table).init(allocator);
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
        var iterator = self.tables.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.tables.deinit();
        self.pager.deinit();
        self.allocator.destroy(self);
    }

    /// Get storage statistics
    pub fn getStats(self: *Self) StorageStats {
        return StorageStats{
            .table_count = self.tables.count(),
            .is_memory = self.is_memory,
            .page_count = self.pager.getPageCount(),
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
    is_memory: bool,
    page_count: u32,
};

test "storage engine creation" {
    try std.testing.expect(true); // Placeholder
}

test "table operations" {
    try std.testing.expect(true); // Placeholder
}
