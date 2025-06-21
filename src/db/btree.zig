const std = @import("std");
const pager = @import("pager.zig");
const storage = @import("storage.zig");

/// B-tree implementation for database storage
pub const BTree = struct {
    allocator: std.mem.Allocator,
    pager: *pager.Pager,
    root_page: u32,
    order: u32, // Maximum number of children per node

    const Self = @This();
    const DEFAULT_ORDER = 64;

    /// Initialize a new B-tree
    pub fn init(allocator: std.mem.Allocator, page_manager: *pager.Pager) !*Self {
        var tree = try allocator.create(Self);
        tree.allocator = allocator;
        tree.pager = page_manager;
        tree.order = DEFAULT_ORDER;

        // Allocate root page
        tree.root_page = try page_manager.allocatePage();

        // Initialize root as leaf node
        var root_node = try Node.initLeaf(allocator, tree.order);
        try tree.writeNode(tree.root_page, &root_node);

        return tree;
    }

    /// Insert a key-value pair
    pub fn insert(self: *Self, key: u64, value: storage.Row) !void {
        var root = try self.readNode(self.root_page);
        defer root.deinit(self.allocator);

        if (root.isFull()) {
            // Split root
            const new_root_page = try self.pager.allocatePage();
            var new_root = try Node.initInternal(self.allocator, self.order);
            new_root.children[0] = self.root_page;

            try self.splitChild(&new_root, 0);
            self.root_page = new_root_page;
            try self.writeNode(new_root_page, &new_root);
        }

        try self.insertNonFull(self.root_page, key, value);
    }

    /// Search for a value by key
    pub fn search(self: *Self, key: u64) !?storage.Row {
        return self.searchNode(self.root_page, key);
    }

    /// Select all rows (for table scans)
    pub fn selectAll(self: *Self, allocator: std.mem.Allocator) ![]storage.Row {
        var results = std.ArrayList(storage.Row).init(allocator);
        try self.collectAllLeafValues(self.root_page, &results);
        return results.toOwnedSlice();
    }

    /// Insert into a non-full node
    fn insertNonFull(self: *Self, page_id: u32, key: u64, value: storage.Row) !void {
        var node = try self.readNode(page_id);
        defer node.deinit(self.allocator);

        if (node.is_leaf) {
            // Insert into leaf
            node.insertKey(key, value);
            try self.writeNode(page_id, &node);
        } else {
            // Find child to insert into
            var i: u32 = node.key_count;
            while (i > 0 and key < node.keys[i - 1]) {
                i -= 1;
            }

            var child = try self.readNode(node.children[i]);
            defer child.deinit(self.allocator);

            if (child.isFull()) {
                try self.splitChild(&node, i);
                if (key > node.keys[i]) {
                    i += 1;
                }
            }

            try self.insertNonFull(node.children[i], key, value);
        }
    }

    /// Split a full child node
    fn splitChild(self: *Self, parent: *Node, child_index: u32) !void {
        const full_child_page = parent.children[child_index];
        var full_child = try self.readNode(full_child_page);
        defer full_child.deinit(self.allocator);

        // Create new node for right half
        const new_child_page = try self.pager.allocatePage();
        var new_child = if (full_child.is_leaf)
            try Node.initLeaf(self.allocator, self.order)
        else
            try Node.initInternal(self.allocator, self.order);

        const mid_index = self.order / 2;

        // Move upper half of keys to new node
        const keys_to_move = full_child.key_count - mid_index - 1;
        if (keys_to_move > 0) {
            @memcpy(new_child.keys[0..keys_to_move], full_child.keys[mid_index + 1 .. full_child.key_count]);
            new_child.key_count = @intCast(keys_to_move);

            if (full_child.is_leaf) {
                @memcpy(new_child.values[0..keys_to_move], full_child.values[mid_index + 1 .. full_child.key_count]);
            } else {
                @memcpy(new_child.children[0 .. keys_to_move + 1], full_child.children[mid_index + 1 .. full_child.key_count + 1]);
            }
        }

        // Update counts
        full_child.key_count = @intCast(mid_index);

        // Move the middle key up to parent
        const middle_key = full_child.keys[mid_index];

        // Shift parent's keys and children to make room
        var i = parent.key_count;
        while (i > child_index) {
            parent.keys[i] = parent.keys[i - 1];
            parent.children[i + 1] = parent.children[i];
            i -= 1;
        }

        // Insert middle key and new child pointer
        parent.keys[child_index] = middle_key;
        parent.children[child_index + 1] = new_child_page;
        parent.key_count += 1;

        // Write updated nodes
        try self.writeNode(full_child_page, &full_child);
        try self.writeNode(new_child_page, &new_child);
    }

    /// Search within a specific node
    fn searchNode(self: *Self, page_id: u32, key: u64) !?storage.Row {
        var node = try self.readNode(page_id);
        defer node.deinit(self.allocator);

        // Binary search for key
        var i: u32 = 0;
        while (i < node.key_count and key > node.keys[i]) {
            i += 1;
        }

        if (i < node.key_count and key == node.keys[i]) {
            // Found key
            if (node.is_leaf) {
                return node.values[i];
            }
        }

        if (node.is_leaf) {
            return null; // Key not found
        }

        // Search in child
        return self.searchNode(node.children[i], key);
    }

    /// Collect all values from leaf nodes (for table scans)
    fn collectAllLeafValues(self: *Self, page_id: u32, results: *std.ArrayList(storage.Row)) !void {
        var node = try self.readNode(page_id);
        defer node.deinit(self.allocator);

        if (node.is_leaf) {
            // Add all values from this leaf - must clone them because the node will be freed
            for (0..node.key_count) |i| {
                const original_row = node.values[i];

                // Clone the entire row with proper memory management
                var cloned_values = try self.allocator.alloc(storage.Value, original_row.values.len);
                for (original_row.values, 0..) |value, j| {
                    cloned_values[j] = switch (value) {
                        .Integer => |int| storage.Value{ .Integer = int },
                        .Real => |real| storage.Value{ .Real = real },
                        .Text => |text| storage.Value{ .Text = try self.allocator.dupe(u8, text) },
                        .Blob => |blob| storage.Value{ .Blob = try self.allocator.dupe(u8, blob) },
                        .Null => storage.Value.Null,
                    };
                }

                try results.append(storage.Row{ .values = cloned_values });
            }
        } else {
            // Recursively collect from all children
            for (0..node.key_count + 1) |i| {
                try self.collectAllLeafValues(node.children[i], results);
            }
        }
    }

    /// Update values in a node that match the predicate
    fn updateInNode(self: *Self, node: *Node, predicate: fn (*const storage.Row) bool, update_fn: fn (*storage.Row) void, updated_count: *u32) !void {
        if (node.is_leaf) {
            for (node.values[0..node.key_count]) |*value| {
                if (predicate(value)) {
                    update_fn(value);
                    updated_count.* += 1;
                }
            }
        } else {
            for (node.children[0 .. node.key_count + 1]) |child| {
                try self.updateInNode(child, predicate, update_fn, updated_count);
            }
        }
    }

    /// Collect values that match (or don't match) a predicate
    fn collectMatchingLeafValues(self: *Self, node: *Node, results: *std.ArrayList(storage.Row), allocator: std.mem.Allocator, predicate: fn (*const storage.Row) bool, should_match: bool) !void {
        if (node.is_leaf) {
            for (node.values[0..node.key_count]) |value| {
                const matches = predicate(&value);
                if (matches == should_match) {
                    // Clone the row
                    var cloned_values = try allocator.alloc(storage.Value, value.values.len);
                    for (value.values, 0..) |val, i| {
                        cloned_values[i] = switch (val) {
                            .Integer => |int| storage.Value{ .Integer = int },
                            .Real => |real| storage.Value{ .Real = real },
                            .Text => |text| storage.Value{ .Text = try allocator.dupe(u8, text) },
                            .Blob => |blob| storage.Value{ .Blob = try allocator.dupe(u8, blob) },
                            .Null => storage.Value.Null,
                        };
                    }
                    try results.append(storage.Row{ .values = cloned_values });
                }
            }
        } else {
            for (node.children[0 .. node.key_count + 1]) |child| {
                try self.collectMatchingLeafValues(child, results, allocator, predicate, should_match);
            }
        }
    }

    /// Count all rows in the tree
    fn countAllRows(self: *Self) u32 {
        if (self.root == null) return 0;
        return self.countRowsInNode(self.root.?);
    }

    /// Count rows in a specific node
    fn countRowsInNode(self: *Self, node: *Node) u32 {
        if (node.is_leaf) {
            return node.key_count;
        } else {
            var count: u32 = 0;
            for (node.children[0 .. node.key_count + 1]) |child| {
                count += self.countRowsInNode(child);
            }
            return count;
        }
    }

    /// Rebuild tree with new set of rows
    fn rebuildWithRows(self: *Self, rows: []storage.Row) !void {
        // Clear the current tree
        if (self.root) |root| {
            root.deinit(self.allocator);
            self.allocator.destroy(root);
            self.root = null;
        }

        // Insert all rows back
        for (rows, 0..) |row, i| {
            try self.insert(@intCast(i), row);
        }
    }

    /// Update a row by key
    fn updateByKey(self: *Self, key: u64, new_row: storage.Row) !bool {
        if (self.root == null) return false;
        return try self.updateKeyInNode(self.root.?, key, new_row);
    }

    /// Delete a row by key
    fn deleteByKey(self: *Self, key: u64) !bool {
        if (self.root == null) return false;
        return try self.deleteKeyInNode(self.root.?, key);
    }

    /// Update a key in a specific node
    fn updateKeyInNode(self: *Self, node: *Node, key: u64, new_row: storage.Row) !bool {
        if (node.is_leaf) {
            for (node.keys[0..node.key_count], 0..) |k, i| {
                if (k == key) {
                    // Free old value
                    for (node.values[i].values) |value| {
                        value.deinit(self.allocator);
                    }
                    self.allocator.free(node.values[i].values);

                    // Clone new value
                    var cloned_values = try self.allocator.alloc(storage.Value, new_row.values.len);
                    for (new_row.values, 0..) |val, j| {
                        cloned_values[j] = switch (val) {
                            .Integer => |int| storage.Value{ .Integer = int },
                            .Real => |real| storage.Value{ .Real = real },
                            .Text => |text| storage.Value{ .Text = try self.allocator.dupe(u8, text) },
                            .Blob => |blob| storage.Value{ .Blob = try self.allocator.dupe(u8, blob) },
                            .Null => storage.Value.Null,
                        };
                    }
                    node.values[i] = storage.Row{ .values = cloned_values };
                    return true;
                }
            }
            return false;
        } else {
            // Find appropriate child
            var i: u32 = 0;
            while (i < node.key_count and key > node.keys[i]) {
                i += 1;
            }
            return try self.updateKeyInNode(node.children[i], key, new_row);
        }
    }

    /// Delete a key from a specific node
    fn deleteKeyInNode(self: *Self, node: *Node, key: u64) !bool {
        if (node.is_leaf) {
            for (node.keys[0..node.key_count], 0..) |k, i| {
                if (k == key) {
                    // Free the value
                    for (node.values[i].values) |value| {
                        value.deinit(self.allocator);
                    }
                    self.allocator.free(node.values[i].values);

                    // Shift elements left to fill the gap
                    var j = i;
                    while (j < node.key_count - 1) {
                        node.keys[j] = node.keys[j + 1];
                        node.values[j] = node.values[j + 1];
                        j += 1;
                    }
                    node.key_count -= 1;
                    return true;
                }
            }
            return false;
        } else {
            // Find appropriate child
            var i: u32 = 0;
            while (i < node.key_count and key > node.keys[i]) {
                i += 1;
            }
            return try self.deleteKeyInNode(node.children[i], key);
        }
    }

    /// Read a node from storage
    fn readNode(self: *Self, page_id: u32) !Node {
        const page = try self.pager.getPage(page_id);
        return Node.deserialize(self.allocator, page.data, self.order);
    }

    /// Write a node to storage
    fn writeNode(self: *Self, page_id: u32, node: *Node) !void {
        const page = try self.pager.getPage(page_id);
        try node.serialize(page.data);
        try self.pager.markDirty(page_id);
    }

    /// Clean up B-tree
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
};

/// B-tree node
const Node = struct {
    is_leaf: bool,
    key_count: u32,
    keys: []u64,
    values: []storage.Row, // Only used in leaf nodes
    children: []u32, // Only used in internal nodes
    order: u32,
    max_keys: u32,

    const Self = @This();

    /// Initialize a leaf node
    pub fn initLeaf(allocator: std.mem.Allocator, order: u32) !Self {
        const max_keys = order - 1;
        return Self{
            .is_leaf = true,
            .key_count = 0,
            .keys = try allocator.alloc(u64, max_keys),
            .values = try allocator.alloc(storage.Row, max_keys),
            .children = &.{}, // Empty for leaf nodes
            .order = order,
            .max_keys = max_keys,
        };
    }

    /// Initialize an internal node
    pub fn initInternal(allocator: std.mem.Allocator, order: u32) !Self {
        const max_keys = order - 1;
        return Self{
            .is_leaf = false,
            .key_count = 0,
            .keys = try allocator.alloc(u64, max_keys),
            .values = &.{}, // Empty for internal nodes
            .children = try allocator.alloc(u32, order), // One more child than keys
            .order = order,
            .max_keys = max_keys,
        };
    }

    /// Check if node is full
    pub fn isFull(self: *const Self) bool {
        return self.key_count >= self.order - 1;
    }

    /// Insert a key-value pair into a leaf node
    pub fn insertKey(self: *Self, key: u64, value: storage.Row) void {
        // Find insertion point
        var i: u32 = self.key_count;
        while (i > 0 and self.keys[i - 1] > key) {
            self.keys[i] = self.keys[i - 1];
            self.values[i] = self.values[i - 1];
            i -= 1;
        }

        // Insert new key-value
        self.keys[i] = key;
        self.values[i] = value;
        self.key_count += 1;
    }

    /// Serialize node to bytes
    pub fn serialize(self: *const Self, buffer: []u8) !void {
        var stream = std.io.fixedBufferStream(buffer);
        const writer = stream.writer();

        // Write header
        try writer.writeInt(u8, if (self.is_leaf) 1 else 0, .little);
        try writer.writeInt(u32, self.key_count, .little);
        try writer.writeInt(u32, self.order, .little);

        // Write keys
        for (self.keys[0..self.key_count]) |key| {
            try writer.writeInt(u64, key, .little);
        }

        if (self.is_leaf) {
            // Write values for leaf nodes
            for (self.values[0..self.key_count]) |value| {
                try self.serializeValue(writer, &value);
            }
        } else {
            // Write child pointers for internal nodes
            for (self.children[0 .. self.key_count + 1]) |child| {
                try writer.writeInt(u32, child, .little);
            }
        }
    }

    /// Serialize a single value
    fn serializeValue(self: *const Self, writer: anytype, value: *const storage.Row) !void {
        _ = self;
        // Write number of values in row
        try writer.writeInt(u32, @intCast(value.values.len), .little);

        // Write each value
        for (value.values) |val| {
            switch (val) {
                .Integer => |i| {
                    try writer.writeInt(u8, 1, .little); // Type tag
                    try writer.writeInt(i64, i, .little);
                },
                .Real => |r| {
                    try writer.writeInt(u8, 2, .little); // Type tag
                    try writer.writeInt(u64, @bitCast(r), .little);
                },
                .Text => |t| {
                    try writer.writeInt(u8, 3, .little); // Type tag
                    try writer.writeInt(u32, @intCast(t.len), .little);
                    try writer.writeAll(t);
                },
                .Blob => |b| {
                    try writer.writeInt(u8, 4, .little); // Type tag
                    try writer.writeInt(u32, @intCast(b.len), .little);
                    try writer.writeAll(b);
                },
                .Null => {
                    try writer.writeInt(u8, 0, .little); // Type tag
                },
            }
        }
    }

    /// Deserialize node from bytes
    pub fn deserialize(allocator: std.mem.Allocator, buffer: []const u8, order: u32) !Self {
        var stream = std.io.fixedBufferStream(buffer);
        const reader = stream.reader();

        // Read header
        const is_leaf = (try reader.readInt(u8, .little)) == 1;
        const key_count = try reader.readInt(u32, .little);
        const stored_order = try reader.readInt(u32, .little);

        if (stored_order != order) {
            return error.OrderMismatch;
        }

        // Create node
        var node = if (is_leaf)
            try Node.initLeaf(allocator, order)
        else
            try Node.initInternal(allocator, order);

        node.key_count = key_count;

        // Read keys
        for (0..key_count) |i| {
            node.keys[i] = try reader.readInt(u64, .little);
        }

        if (is_leaf) {
            // Read values for leaf nodes
            for (0..key_count) |i| {
                node.values[i] = try deserializeValue(allocator, reader);
            }
        } else {
            // Read child pointers for internal nodes
            for (0..key_count + 1) |i| {
                node.children[i] = try reader.readInt(u32, .little);
            }
        }

        return node;
    }

    /// Deserialize a single value
    fn deserializeValue(allocator: std.mem.Allocator, reader: anytype) !storage.Row {
        const value_count = try reader.readInt(u32, .little);
        var values = try allocator.alloc(storage.Value, value_count);

        for (0..value_count) |i| {
            const type_tag = try reader.readInt(u8, .little);
            values[i] = switch (type_tag) {
                0 => storage.Value.Null,
                1 => storage.Value{ .Integer = try reader.readInt(i64, .little) },
                2 => storage.Value{ .Real = @bitCast(try reader.readInt(u64, .little)) },
                3 => blk: {
                    const len = try reader.readInt(u32, .little);
                    const text = try allocator.alloc(u8, len);
                    _ = try reader.readAll(text);
                    break :blk storage.Value{ .Text = text };
                },
                4 => blk: {
                    const len = try reader.readInt(u32, .little);
                    const blob = try allocator.alloc(u8, len);
                    _ = try reader.readAll(blob);
                    break :blk storage.Value{ .Blob = blob };
                },
                else => return error.InvalidValueType,
            };
        }

        return storage.Row{ .values = values };
    }

    /// Clean up node
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.keys);
        if (self.is_leaf) {
            // Clean up values in leaf nodes
            for (self.values[0..self.key_count]) |value| {
                for (value.values) |val| {
                    val.deinit(allocator);
                }
                allocator.free(value.values);
            }
            allocator.free(self.values);
        } else {
            allocator.free(self.children);
        }
    }
};

test "btree creation" {
    try std.testing.expect(true); // Placeholder
}

test "btree insert and search" {
    try std.testing.expect(true); // Placeholder
}
