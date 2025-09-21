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
        defer root_node.deinit(allocator); // Clean up after writing to storage
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
        var results = std.array_list.Managed(storage.Row).init(allocator);
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
            // Find child to insert into using binary search
            const search_result = node.binarySearchKey(key);
            var child_index = search_result.index;
            
            // If we found the exact key, we still need to go to the right child
            if (search_result.found) {
                child_index += 1;
            }

            var child = try self.readNode(node.children[child_index]);
            defer child.deinit(self.allocator);

            if (child.isFull()) {
                try self.splitChild(&node, child_index);
                // After split, check if we need to adjust child index
                const new_search = node.binarySearchKey(key);
                child_index = if (new_search.found or key > node.keys[new_search.index]) 
                    new_search.index + 1 
                else 
                    new_search.index;
            }

            try self.insertNonFull(node.children[child_index], key, value);
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

    /// Search within a specific node using binary search
    fn searchNode(self: *Self, page_id: u32, key: u64) !?storage.Row {
        var node = try self.readNode(page_id);
        defer node.deinit(self.allocator);

        // Binary search for key
        const search_result = node.binarySearchKey(key);
        
        if (search_result.found) {
            // Found exact key
            if (node.is_leaf) {
                return node.values[search_result.index];
            }
            // For internal nodes, we need to continue searching
        }

        if (node.is_leaf) {
            return null; // Key not found
        }

        // Search in appropriate child
        return self.searchNode(node.children[search_result.index], key);
    }

    /// Collect all values from leaf nodes (for table scans)
    fn collectAllLeafValues(self: *Self, page_id: u32, results: *std.array_list.Managed(storage.Row)) !void {
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
                        .Parameter => |param_index| storage.Value{ .Parameter = param_index },
                        .FunctionCall => |func| storage.Value{ .FunctionCall = try self.cloneStorageFunctionCall(func) },
                        // PostgreSQL compatibility values
                        .JSON => |json| storage.Value{ .JSON = try self.allocator.dupe(u8, json) },
                        .JSONB => |jsonb| storage.Value{ .JSONB = storage.JSONBValue.init(self.allocator, try jsonb.toString(self.allocator)) catch |err| blk: {
                            std.debug.print("JSONB clone error: {}\n", .{err});
                            break :blk storage.JSONBValue.init(self.allocator, "{}") catch unreachable;
                        } },
                        .UUID => |uuid| storage.Value{ .UUID = uuid },
                        .Array => |array| storage.Value{ .Array = storage.ArrayValue{
                            .element_type = array.element_type,
                            .elements = blk: {
                                var cloned_elements = try self.allocator.alloc(storage.Value, array.elements.len);
                                for (array.elements, 0..) |elem, k| {
                                    // Recursively clone array elements (simplified - could cause stack overflow for deeply nested arrays)
                                    cloned_elements[k] = switch (elem) {
                                        .Integer => |int| storage.Value{ .Integer = int },
                                        .Text => |text| storage.Value{ .Text = try self.allocator.dupe(u8, text) },
                                        .Real => |real| storage.Value{ .Real = real },
                                        else => storage.Value.Null, // Simplified - handle complex nested types as null
                                    };
                                }
                                break :blk cloned_elements;
                            },
                        } },
                        .Boolean => |bool_val| storage.Value{ .Boolean = bool_val },
                        .Timestamp => |ts| storage.Value{ .Timestamp = ts },
                        .TimestampTZ => |tstz| storage.Value{ .TimestampTZ = storage.TimestampTZValue{
                            .timestamp = tstz.timestamp,
                            .timezone = try self.allocator.dupe(u8, tstz.timezone),
                        } },
                        .Date => |date| storage.Value{ .Date = date },
                        .Time => |time| storage.Value{ .Time = time },
                        .Interval => |interval| storage.Value{ .Interval = interval },
                        .Numeric => |numeric| storage.Value{ .Numeric = storage.NumericValue{
                            .precision = numeric.precision,
                            .scale = numeric.scale,
                            .digits = try self.allocator.dupe(u8, numeric.digits),
                            .is_negative = numeric.is_negative,
                        } },
                        .SmallInt => |si| storage.Value{ .SmallInt = si },
                        .BigInt => |bi| storage.Value{ .BigInt = bi },
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
    fn collectMatchingLeafValues(self: *Self, node: *Node, results: *std.array_list.Managed(storage.Row), allocator: std.mem.Allocator, predicate: fn (*const storage.Row) bool, should_match: bool) !void {
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

    /// Update a key in a specific node using binary search
    fn updateKeyInNode(self: *Self, node: *Node, key: u64, new_row: storage.Row) !bool {
        if (node.is_leaf) {
            const search_result = node.binarySearchKey(key);
            if (search_result.found) {
                const i = search_result.index;
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
            return false;
        } else {
            // Find appropriate child using binary search
            const search_result = node.binarySearchKey(key);
            const child_index = if (search_result.found) search_result.index + 1 else search_result.index;
            return try self.updateKeyInNode(node.children[child_index], key, new_row);
        }
    }

    /// Delete a key from a specific node using binary search
    fn deleteKeyInNode(self: *Self, node: *Node, key: u64) !bool {
        if (node.is_leaf) {
            const search_result = node.binarySearchKey(key);
            if (search_result.found) {
                const i = search_result.index;
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
            return false;
        } else {
            // Find appropriate child using binary search
            const search_result = node.binarySearchKey(key);
            const child_index = if (search_result.found) search_result.index + 1 else search_result.index;
            return try self.deleteKeyInNode(node.children[child_index], key);
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
        _ = try node.serialize(page.data, self.allocator);
        try self.pager.markDirty(page_id);
    }

    /// Clean up B-tree
    pub fn deinit(self: *Self) void {
        // Recursively clean up all nodes starting from root
        self.cleanupNodeRecursive(self.root_page) catch {
            // If cleanup fails, we still need to free the BTree struct
            // This is a best-effort cleanup to prevent memory leaks
        };

        self.allocator.destroy(self);
    }

    /// Recursively clean up a node and all its children
    fn cleanupNodeRecursive(self: *Self, page_id: u32) !void {
        var node = self.readNode(page_id) catch {
            // If we can't read the node, skip it (might be already freed)
            return;
        };
        defer node.deinit(self.allocator);

        // If it's an internal node, recursively clean up children
        if (!node.is_leaf) {
            for (node.children[0..node.key_count + 1]) |child_page| {
                if (child_page > 0) {
                    self.cleanupNodeRecursive(child_page) catch {
                        // Continue cleanup even if some children fail
                    };
                }
            }
        }
    }

    /// Clone a storage function call
    fn cloneStorageFunctionCall(self: *Self, function_call: storage.Column.FunctionCall) !storage.Column.FunctionCall {
        var cloned_args = try self.allocator.alloc(storage.Column.FunctionArgument, function_call.arguments.len);
        for (function_call.arguments, 0..) |arg, i| {
            cloned_args[i] = try self.cloneStorageFunctionArgument(arg);
        }

        return storage.Column.FunctionCall{
            .name = try self.allocator.dupe(u8, function_call.name),
            .arguments = cloned_args,
        };
    }

    /// Clone a storage function argument
    fn cloneStorageFunctionArgument(self: *Self, arg: storage.Column.FunctionArgument) !storage.Column.FunctionArgument {
        return switch (arg) {
            .Literal => |literal| {
                const cloned_literal = try self.cloneValueSimple(literal);
                return storage.Column.FunctionArgument{ .Literal = cloned_literal };
            },
            .Column => |column| {
                return storage.Column.FunctionArgument{ .Column = try self.allocator.dupe(u8, column) };
            },
            .Parameter => |param_index| {
                return storage.Column.FunctionArgument{ .Parameter = param_index };
            },
        };
    }

    /// Clone a storage value (simple version to avoid infinite recursion)
    fn cloneValueSimple(self: *Self, value: storage.Value) !storage.Value {
        return switch (value) {
            .Integer => |i| storage.Value{ .Integer = i },
            .Real => |r| storage.Value{ .Real = r },
            .Text => |t| storage.Value{ .Text = try self.allocator.dupe(u8, t) },
            .Blob => |b| storage.Value{ .Blob = try self.allocator.dupe(u8, b) },
            .Null => storage.Value.Null,
            .Parameter => |param_index| storage.Value{ .Parameter = param_index },
            .FunctionCall => |_| storage.Value.Null, // Simplified - function calls shouldn't be in stored values
            .JSON => |json| storage.Value{ .JSON = try self.allocator.dupe(u8, json) },
            .JSONB => |jsonb| storage.Value{ .JSONB = storage.JSONBValue.init(self.allocator, try jsonb.toString(self.allocator)) catch return storage.Value.Null },
            .UUID => |uuid| storage.Value{ .UUID = uuid },
            .Array => |array| storage.Value{ .Array = storage.ArrayValue{
                .element_type = array.element_type,
                .elements = try self.allocator.dupe(storage.Value, array.elements),
            } },
            .Boolean => |b| storage.Value{ .Boolean = b },
            .Timestamp => |ts| storage.Value{ .Timestamp = ts },
            .TimestampTZ => |tstz| storage.Value{ .TimestampTZ = tstz },
            .Date => |d| storage.Value{ .Date = d },
            .Time => |t| storage.Value{ .Time = t },
            .Interval => |i| storage.Value{ .Interval = i },
            .Numeric => |n| storage.Value{ .Numeric = n },
            .SmallInt => |si| storage.Value{ .SmallInt = si },
            .BigInt => |bi| storage.Value{ .BigInt = bi },
        };
    }
};

/// B-tree node
pub const Node = struct {
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

    /// Binary search result structure
    const SearchResult = struct {
        index: u32,
        found: bool,
    };

    /// Binary search for a key in the node's keys array
    pub fn binarySearchKey(self: *const Self, key: u64) SearchResult {
        if (self.key_count == 0) {
            return SearchResult{ .index = 0, .found = false };
        }

        var left: u32 = 0;
        var right: u32 = self.key_count;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const mid_key = self.keys[mid];

            if (mid_key == key) {
                return SearchResult{ .index = mid, .found = true };
            } else if (mid_key < key) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        return SearchResult{ .index = left, .found = false };
    }

    /// Insert a key-value pair into a leaf node using binary search
    pub fn insertKey(self: *Self, key: u64, value: storage.Row) void {
        // Find insertion point using binary search
        const search_result = self.binarySearchKey(key);
        const insert_index = search_result.index;

        // Shift elements to the right to make space
        var i: u32 = self.key_count;
        while (i > insert_index) {
            self.keys[i] = self.keys[i - 1];
            self.values[i] = self.values[i - 1];
            i -= 1;
        }

        // Insert new key-value
        self.keys[insert_index] = key;
        self.values[insert_index] = value;
        self.key_count += 1;
    }

    /// Serialize node to bytes
    pub fn serialize(self: *const Self, buffer: []u8, allocator: std.mem.Allocator) !usize {
        var pos: usize = 0;

        // Ensure we have minimum buffer space for header
        if (buffer.len < 9) return error.BufferTooSmall;

        // Write header
        buffer[pos] = if (self.is_leaf) 1 else 0;
        pos += 1;

        std.mem.writeInt(u32, buffer[pos..][0..4], self.key_count, .little);
        pos += 4;

        std.mem.writeInt(u32, buffer[pos..][0..4], self.order, .little);
        pos += 4;

        // Write keys
        for (self.keys[0..self.key_count]) |key| {
            if (pos + 8 > buffer.len) return error.BufferTooSmall;
            std.mem.writeInt(u64, buffer[pos..][0..8], key, .little);
            pos += 8;
        }

        if (self.is_leaf) {
            // Write values for leaf nodes
            for (self.values[0..self.key_count]) |value| {
                if (pos >= buffer.len) return error.BufferTooSmall;
                const bytes_written = try self.serializeValue(buffer[pos..], &value, allocator);
                pos += bytes_written;
            }
        } else {
            // Write child pointers for internal nodes
            for (self.children[0 .. self.key_count + 1]) |child| {
                if (pos + 4 > buffer.len) return error.BufferTooSmall;
                std.mem.writeInt(u32, buffer[pos..][0..4], child, .little);
                pos += 4;
            }
        }
        
        return pos;
    }

    /// Serialize a single value
    fn serializeValue(self: *const Self, buffer: []u8, value: *const storage.Row, allocator: std.mem.Allocator) !usize {
        _ = self;
        var pos: usize = 0;

        // Ensure we have space for the row value count
        if (buffer.len < 4) return error.BufferTooSmall;

        // Write number of values in row
        std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(value.values.len), .little);
        pos += 4;

        // Write each value
        for (value.values) |val| {
            switch (val) {
                .Integer => |i| {
                    if (pos + 9 > buffer.len) return error.BufferTooSmall; // 1 byte tag + 8 bytes data
                    buffer[pos] = 1; // Type tag
                    pos += 1;
                    std.mem.writeInt(i64, buffer[pos..][0..8], i, .little);
                    pos += 8;
                },
                .Real => |r| {
                    if (pos + 9 > buffer.len) return error.BufferTooSmall; // 1 byte tag + 8 bytes data
                    buffer[pos] = 2; // Type tag
                    pos += 1;
                    std.mem.writeInt(u64, buffer[pos..][0..8], @bitCast(r), .little);
                    pos += 8;
                },
                .Text => |t| {
                    if (pos + 5 + t.len > buffer.len) return error.BufferTooSmall; // 1 byte tag + 4 bytes length + text
                    buffer[pos] = 3; // Type tag
                    pos += 1;
                    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(t.len), .little);
                    pos += 4;
                    @memcpy(buffer[pos..][0..t.len], t);
                    pos += t.len;
                },
                .Blob => |b| {
                    if (pos + 5 + b.len > buffer.len) return error.BufferTooSmall; // 1 byte tag + 4 bytes length + blob
                    buffer[pos] = 4; // Type tag
                    pos += 1;
                    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(b.len), .little);
                    pos += 4;
                    @memcpy(buffer[pos..][0..b.len], b);
                    pos += b.len;
                },
                .Null => {
                    if (pos + 1 > buffer.len) return error.BufferTooSmall;
                    buffer[pos] = 0; // Type tag
                    pos += 1;
                },
                .Parameter => |param_index| {
                    if (pos + 5 > buffer.len) return error.BufferTooSmall; // 1 byte tag + 4 bytes data
                    buffer[pos] = 5; // Type tag
                    pos += 1;
                    std.mem.writeInt(u32, buffer[pos..][0..4], param_index, .little);
                    pos += 4;
                },
                .FunctionCall => |_| {
                    // Function calls should be evaluated before storage - this is a fallback
                    if (pos + 1 > buffer.len) return error.BufferTooSmall;
                    buffer[pos] = 0; // Store as NULL
                    pos += 1;
                },
                // PostgreSQL compatibility values - simplified serialization
                .JSON => |j| {
                    buffer[pos] = 6; // Type tag
                    pos += 1;
                    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(j.len), .little);
                    pos += 4;
                    @memcpy(buffer[pos..][0..j.len], j);
                    pos += j.len;
                },
                .JSONB => |jsonb| {
                    buffer[pos] = 7; // Type tag
                    pos += 1;
                    const json_str = jsonb.toString(allocator) catch "";
                    defer if (json_str.len > 0) allocator.free(json_str);
                    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(json_str.len), .little);
                    pos += 4;
                    @memcpy(buffer[pos..][0..json_str.len], json_str);
                    pos += json_str.len;
                },
                .UUID => |uuid| {
                    buffer[pos] = 8; // Type tag
                    pos += 1;
                    @memcpy(buffer[pos..][0..16], &uuid);
                    pos += 16;
                },
                .Array => |array| {
                    buffer[pos] = 9; // Type tag
                    pos += 1;
                    const array_str = array.toString(allocator) catch "";
                    defer if (array_str.len > 0) allocator.free(array_str);
                    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(array_str.len), .little);
                    pos += 4;
                    @memcpy(buffer[pos..][0..array_str.len], array_str);
                    pos += array_str.len;
                },
                .Boolean => |b| {
                    if (pos + 2 > buffer.len) return error.BufferTooSmall; // 1 byte tag + 1 byte data
                    buffer[pos] = 10; // Type tag
                    pos += 1;
                    buffer[pos] = if (b) 1 else 0;
                    pos += 1;
                },
                .Timestamp => |ts| {
                    if (pos + 9 > buffer.len) return error.BufferTooSmall; // 1 byte tag + 8 bytes data
                    buffer[pos] = 11; // Type tag
                    pos += 1;
                    std.mem.writeInt(i64, buffer[pos..][0..8], ts, .little);
                    pos += 8;
                },
                .TimestampTZ => |tstz| {
                    if (pos + 13 + tstz.timezone.len > buffer.len) return error.BufferTooSmall; // 1 byte tag + 8 bytes timestamp + 4 bytes len + timezone
                    buffer[pos] = 12; // Type tag
                    pos += 1;
                    std.mem.writeInt(i64, buffer[pos..][0..8], tstz.timestamp, .little);
                    pos += 8;
                    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(tstz.timezone.len), .little);
                    pos += 4;
                    @memcpy(buffer[pos..][0..tstz.timezone.len], tstz.timezone);
                    pos += tstz.timezone.len;
                },
                .Date => |d| {
                    if (pos + 5 > buffer.len) return error.BufferTooSmall; // 1 byte tag + 4 bytes data
                    buffer[pos] = 13; // Type tag
                    pos += 1;
                    std.mem.writeInt(i32, buffer[pos..][0..4], d, .little);
                    pos += 4;
                },
                .Time => |t| {
                    if (pos + 9 > buffer.len) return error.BufferTooSmall; // 1 byte tag + 8 bytes data
                    buffer[pos] = 14; // Type tag
                    pos += 1;
                    std.mem.writeInt(i64, buffer[pos..][0..8], t, .little);
                    pos += 8;
                },
                .Interval => |i| {
                    if (pos + 9 > buffer.len) return error.BufferTooSmall; // 1 byte tag + 8 bytes data
                    buffer[pos] = 15; // Type tag
                    pos += 1;
                    std.mem.writeInt(i64, buffer[pos..][0..8], i, .little);
                    pos += 8;
                },
                .Numeric => |n| {
                    if (pos + 10 + n.digits.len > buffer.len) return error.BufferTooSmall; // 1 byte tag + 2+2+1+4 bytes + digits
                    buffer[pos] = 16; // Type tag
                    pos += 1;
                    std.mem.writeInt(u16, buffer[pos..][0..2], n.precision, .little);
                    pos += 2;
                    std.mem.writeInt(u16, buffer[pos..][0..2], n.scale, .little);
                    pos += 2;
                    buffer[pos] = if (n.is_negative) 1 else 0;
                    pos += 1;
                    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(n.digits.len), .little);
                    pos += 4;
                    @memcpy(buffer[pos..][0..n.digits.len], n.digits);
                    pos += n.digits.len;
                },
                .SmallInt => |si| {
                    if (pos + 3 > buffer.len) return error.BufferTooSmall; // 1 byte tag + 2 bytes data
                    buffer[pos] = 17; // Type tag
                    pos += 1;
                    std.mem.writeInt(i16, buffer[pos..][0..2], si, .little);
                    pos += 2;
                },
                .BigInt => |bi| {
                    if (pos + 9 > buffer.len) return error.BufferTooSmall; // 1 byte tag + 8 bytes data
                    buffer[pos] = 18; // Type tag
                    pos += 1;
                    std.mem.writeInt(i64, buffer[pos..][0..8], bi, .little);
                    pos += 8;
                },
            }
        }
        
        return pos;
    }

    /// Deserialize node from bytes
    pub fn deserialize(allocator: std.mem.Allocator, buffer: []const u8, order: u32) !Self {
        if (buffer.len < 9) return error.BufferTooSmall; // Minimum header size
        
        var pos: usize = 0;

        // Read header
        const is_leaf = buffer[pos] == 1;
        pos += 1;
        
        const key_count = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
        
        const stored_order = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;

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
            if (buffer.len < pos + 8) return error.BufferTooSmall;
            node.keys[i] = std.mem.readInt(u64, buffer[pos..][0..8], .little);
            pos += 8;
        }

        if (is_leaf) {
            // Read values for leaf nodes
            for (0..key_count) |i| {
                const value_result = try deserializeValue(allocator, buffer[pos..]);
                node.values[i] = value_result.value;
                pos += value_result.bytes_read;
            }
        } else {
            // Read child pointers for internal nodes
            for (0..key_count + 1) |i| {
                if (buffer.len < pos + 4) return error.BufferTooSmall;
                node.children[i] = std.mem.readInt(u32, buffer[pos..][0..4], .little);
                pos += 4;
            }
        }

        return node;
    }

    /// Result structure for deserializeValue
    const DeserializeValueResult = struct {
        value: storage.Row,
        bytes_read: usize,
    };
    
    /// Deserialize a single value
    fn deserializeValue(allocator: std.mem.Allocator, buffer: []const u8) !DeserializeValueResult {
        if (buffer.len < 4) return error.BufferTooSmall;
        
        var pos: usize = 0;
        
        const value_count = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
        
        var values = try allocator.alloc(storage.Value, value_count);

        for (0..value_count) |i| {
            if (buffer.len < pos + 1) return error.BufferTooSmall;
            const type_tag = buffer[pos];
            pos += 1;
            
            values[i] = switch (type_tag) {
                0 => storage.Value.Null,
                1 => blk: {
                    if (buffer.len < pos + 8) return error.BufferTooSmall;
                    const val = std.mem.readInt(i64, buffer[pos..][0..8], .little);
                    pos += 8;
                    break :blk storage.Value{ .Integer = val };
                },
                2 => blk: {
                    if (buffer.len < pos + 8) return error.BufferTooSmall;
                    const val = std.mem.readInt(u64, buffer[pos..][0..8], .little);
                    pos += 8;
                    break :blk storage.Value{ .Real = @bitCast(val) };
                },
                3 => blk: {
                    if (buffer.len < pos + 4) return error.BufferTooSmall;
                    const len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
                    pos += 4;
                    if (buffer.len < pos + len) return error.BufferTooSmall;
                    const text = try allocator.alloc(u8, len);
                    @memcpy(text, buffer[pos..][0..len]);
                    pos += len;
                    break :blk storage.Value{ .Text = text };
                },
                4 => blk: {
                    if (buffer.len < pos + 4) return error.BufferTooSmall;
                    const len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
                    pos += 4;
                    if (buffer.len < pos + len) return error.BufferTooSmall;
                    const blob = try allocator.alloc(u8, len);
                    @memcpy(blob, buffer[pos..][0..len]);
                    pos += len;
                    break :blk storage.Value{ .Blob = blob };
                },
                5 => blk: {
                    if (buffer.len < pos + 4) return error.BufferTooSmall;
                    const param_index = std.mem.readInt(u32, buffer[pos..][0..4], .little);
                    pos += 4;
                    break :blk storage.Value{ .Parameter = param_index };
                },
                else => return error.InvalidValueType,
            };
        }

        return DeserializeValueResult{
            .value = storage.Row{ .values = values },
            .bytes_read = pos,
        };
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

test "btree binary search performance" {
    const allocator = std.testing.allocator;
    
    // Test binary search on node
    var node = try Node.initLeaf(allocator, 64);
    defer node.deinit(allocator);
    
    // Insert keys in random order
    const keys = [_]u64{ 50, 25, 75, 12, 37, 62, 87, 6, 18, 31, 43, 56, 68, 81, 93 };
    for (keys) |key| {
        var values = try allocator.alloc(storage.Value, 1);
        values[0] = storage.Value{ .Integer = @intCast(key) };
        const value = storage.Row{ .values = values };
        node.insertKey(key, value);
    }
    
    // Test binary search finds all keys
    for (keys) |key| {
        const result = node.binarySearchKey(key);
        try std.testing.expect(result.found);
        try std.testing.expectEqual(key, node.keys[result.index]);
    }
    
    // Test binary search for non-existent keys
    const non_existent = [_]u64{ 1, 100, 49, 51 };
    for (non_existent) |key| {
        const result = node.binarySearchKey(key);
        try std.testing.expect(!result.found);
    }
}

test "btree creation and basic operations" {
    const allocator = std.testing.allocator;
    const pager_instance = try pager.Pager.initMemory(allocator);
    defer pager_instance.deinit();
    
    const btree = try BTree.init(allocator, pager_instance);
    defer btree.deinit();
    
    try std.testing.expect(btree.root_page > 0);
    try std.testing.expectEqual(@as(u32, 64), btree.order);
}

test "btree insert and search comprehensive" {
    const allocator = std.testing.allocator;
    const pager_inst = try pager.Pager.initMemory(allocator);
    defer pager_inst.deinit();
    
    const btree = try BTree.init(allocator, pager_inst);
    defer btree.deinit();
    
    // Insert test data
    const test_keys = [_]u64{ 10, 20, 5, 15, 25, 3, 7, 12, 18, 22, 30 };
    for (test_keys, 0..) |key, i| {
        var values = try allocator.alloc(storage.Value, 2);
        values[0] = storage.Value{ .Integer = @intCast(key) };
        values[1] = storage.Value{ .Text = try std.fmt.allocPrint(allocator, "value_{d}", .{i}) };
        const value = storage.Row{ .values = values };
        try btree.insert(key, value);
    }
    
    // Search for all inserted keys
    for (test_keys) |key| {
        const result = try btree.search(key);
        try std.testing.expect(result != null);
        if (result) |row| {
            try std.testing.expectEqual(storage.Value{ .Integer = @intCast(key) }, row.values[0]);
            allocator.free(row.values[1].Text);
            allocator.free(row.values);
        }
    }
    
    // Search for non-existent key
    const not_found = try btree.search(999);
    try std.testing.expect(not_found == null);
}
