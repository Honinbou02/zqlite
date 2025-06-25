const std = @import("std");
const ast = @import("../parser/ast.zig");
const planner = @import("planner.zig");
const storage = @import("../db/storage.zig");
const db = @import("../db/connection.zig");

/// Virtual machine for executing query plans
pub const VirtualMachine = struct {
    allocator: std.mem.Allocator,
    connection: *db.Connection,

    const Self = @This();

    /// Initialize virtual machine
    pub fn init(allocator: std.mem.Allocator, connection: *db.Connection) Self {
        return Self{
            .allocator = allocator,
            .connection = connection,
        };
    }

    /// Execute a query plan
    pub fn execute(self: *Self, plan: *planner.ExecutionPlan) !ExecutionResult {
        var result = ExecutionResult{
            .rows = std.ArrayList(storage.Row).init(self.allocator),
            .affected_rows = 0,
        };

        for (plan.steps) |*step| {
            try self.executeStep(step, &result);
        }

        return result;
    }

    /// Execute a single step
    fn executeStep(self: *Self, step: *planner.ExecutionStep, result: *ExecutionResult) !void {
        switch (step.*) {
            .TableScan => |*scan| try self.executeTableScan(scan, result),
            .Filter => |*filter| try self.executeFilter(filter, result),
            .Project => |*project| try self.executeProject(project, result),
            .Limit => |*limit| try self.executeLimit(limit, result),
            .Insert => |*insert| try self.executeInsert(insert, result),
            .CreateTable => |*create| try self.executeCreateTable(create, result),
            .Update => |*update| try self.executeUpdate(update, result),
            .Delete => |*delete| try self.executeDelete(delete, result),
            .NestedLoopJoin => |*join| try self.executeNestedLoopJoin(join, result),
            .HashJoin => |*join| try self.executeHashJoin(join, result),
            .Aggregate => |*agg| try self.executeAggregate(agg, result),
            .GroupBy => |*group| try self.executeGroupBy(group, result),
        }
    }

    /// Execute table scan
    fn executeTableScan(self: *Self, scan: *planner.TableScanStep, result: *ExecutionResult) !void {
        const table = self.connection.storage_engine.getTable(scan.table_name) orelse {
            return error.TableNotFound;
        };

        const rows = try table.select(self.allocator);
        defer {
            // Clean up the rows returned by select (they're already cloned by the B-tree)
            for (rows) |row| {
                for (row.values) |value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(row.values);
            }
            self.allocator.free(rows);
        }

        for (rows) |row| {
            // Clone the row again for the result (since we're freeing the original)
            var cloned_values = try self.allocator.alloc(storage.Value, row.values.len);
            for (row.values, 0..) |value, i| {
                cloned_values[i] = try self.cloneValue(value);
            }
            try result.rows.append(storage.Row{ .values = cloned_values });
        }
    }

    /// Execute filter (WHERE clause)
    fn executeFilter(self: *Self, filter: *planner.FilterStep, result: *ExecutionResult) !void {
        var filtered_rows = std.ArrayList(storage.Row).init(self.allocator);

        for (result.rows.items) |row| {
            if (try self.evaluateCondition(&filter.condition, &row)) {
                try filtered_rows.append(row);
            }
        }

        result.rows.deinit();
        result.rows = filtered_rows;
    }

    /// Execute projection (SELECT columns)
    fn executeProject(self: *Self, project: *planner.ProjectStep, result: *ExecutionResult) !void {
        if (project.columns.len == 1 and std.mem.eql(u8, project.columns[0], "*")) {
            // SELECT * - return all columns, no projection needed
            return;
        }

        // Create projected rows with only selected columns
        var projected_rows = std.ArrayList(storage.Row).init(self.allocator);

        for (result.rows.items) |original_row| {
            var projected_values = std.ArrayList(storage.Value).init(self.allocator);

            // For now, we'll assume column order matches project.columns order
            // In a real implementation, we'd need column metadata from the table schema
            for (project.columns, 0..) |col_name, i| {
                if (i < original_row.values.len) {
                    // Clone the value for the projected row
                    const cloned_value = try self.cloneValue(original_row.values[i]);
                    try projected_values.append(cloned_value);
                } else {
                    // Column doesn't exist, add NULL
                    try projected_values.append(storage.Value.Null);
                }
                _ = col_name; // Suppress unused warning for now
            }

            try projected_rows.append(storage.Row{
                .values = try projected_values.toOwnedSlice(),
            });
        }

        // Replace original rows with projected ones
        result.rows.deinit();
        result.rows = projected_rows;
    }

    /// Clone a storage value
    fn cloneValue(self: *Self, value: storage.Value) !storage.Value {
        return switch (value) {
            .Integer => |i| storage.Value{ .Integer = i },
            .Real => |r| storage.Value{ .Real = r },
            .Text => |t| storage.Value{ .Text = try self.allocator.dupe(u8, t) },
            .Blob => |b| storage.Value{ .Blob = try self.allocator.dupe(u8, b) },
            .Null => storage.Value.Null,
        };
    }

    /// Execute limit
    fn executeLimit(self: *Self, limit: *planner.LimitStep, result: *ExecutionResult) !void {
        const start = @min(limit.offset, result.rows.items.len);
        const end = @min(start + limit.count, result.rows.items.len);

        if (start > 0 or end < result.rows.items.len) {
            // Create new slice with limited rows
            var limited_rows = std.ArrayList(storage.Row).init(self.allocator);
            for (result.rows.items[start..end]) |row| {
                try limited_rows.append(row);
            }
            result.rows.deinit();
            result.rows = limited_rows;
        }
    }

    /// Execute insert
    fn executeInsert(self: *Self, insert: *planner.InsertStep, result: *ExecutionResult) !void {
        const table = self.connection.storage_engine.getTable(insert.table_name) orelse {
            return error.TableNotFound;
        };

        for (insert.values) |row_values| {
            // Clone the values to ensure they're owned by the storage engine
            var cloned_values = try self.allocator.alloc(storage.Value, row_values.len);
            for (row_values, 0..) |value, i| {
                cloned_values[i] = try self.cloneValue(value);
            }

            const row = storage.Row{ .values = cloned_values };
            try table.insert(row);
            result.affected_rows += 1;
        }
    }

    /// Execute create table
    fn executeCreateTable(self: *Self, create: *planner.CreateTableStep, result: *ExecutionResult) !void {
        // Check if table exists and if_not_exists is true
        if (create.if_not_exists and self.connection.storage_engine.getTable(create.table_name) != null) {
            return; // Table already exists, skip creation
        }

        // Clone columns for the storage engine (they're owned by the planner otherwise)
        var cloned_columns = try self.allocator.alloc(storage.Column, create.columns.len);
        for (create.columns, 0..) |column, i| {
            cloned_columns[i] = storage.Column{
                .name = try self.allocator.dupe(u8, column.name),
                .data_type = column.data_type,
                .is_primary_key = column.is_primary_key,
                .is_nullable = column.is_nullable,
            };
        }

        const schema = storage.TableSchema{
            .columns = cloned_columns,
        };

        try self.connection.storage_engine.createTable(create.table_name, schema);
        result.affected_rows = 1;
    }

    /// Execute update
    fn executeUpdate(self: *Self, update: *planner.UpdateStep, result: *ExecutionResult) !void {
        const table = self.connection.storage_engine.getTable(update.table_name) orelse {
            return error.TableNotFound;
        };

        // Get all current rows
        const all_rows = try table.select(self.allocator);
        defer {
            for (all_rows) |row| {
                for (row.values) |value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(row.values);
            }
            self.allocator.free(all_rows);
        }

        var updated_count: u32 = 0;
        var updated_rows = std.ArrayList(storage.Row).init(self.allocator);
        defer {
            for (updated_rows.items) |row| {
                for (row.values) |value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(row.values);
            }
            updated_rows.deinit();
        }

        for (all_rows) |row| {
            // Check if row matches condition
            var matches = true;
            if (update.condition) |condition| {
                matches = try self.evaluateCondition(&condition, &row);
            }

            if (matches) {
                // Create updated row by cloning the original and applying changes
                var updated_values = try self.allocator.alloc(storage.Value, row.values.len);
                for (row.values, 0..) |value, i| {
                    updated_values[i] = try self.cloneValue(value);
                }

                // Apply assignments
                for (update.assignments) |assignment| {
                    // For simplicity, update the first column (in a real implementation,
                    // we'd need proper column name to index mapping from the table schema)
                    if (updated_values.len > 0) {
                        updated_values[0].deinit(self.allocator);
                        updated_values[0] = try self.cloneValue(assignment.value);
                    }
                    _ = assignment.column; // Suppress unused warning for now
                }

                try updated_rows.append(storage.Row{ .values = updated_values });
                updated_count += 1;
            } else {
                // Keep the original row unchanged
                var cloned_values = try self.allocator.alloc(storage.Value, row.values.len);
                for (row.values, 0..) |value, i| {
                    cloned_values[i] = try self.cloneValue(value);
                }
                try updated_rows.append(storage.Row{ .values = cloned_values });
            }
        }

        // Replace the table data with updated rows
        // For now, we'll recreate the table (in a real implementation, we'd have proper update methods)
        const table_name = try self.allocator.dupe(u8, update.table_name);
        defer self.allocator.free(table_name);

        // Get table schema
        const schema = table.schema;

        // Drop and recreate table with updated data
        try self.connection.storage_engine.dropTable(update.table_name);
        try self.connection.storage_engine.createTable(table_name, schema);

        // Reinsert all rows
        const new_table = self.connection.storage_engine.getTable(update.table_name).?;
        for (updated_rows.items) |row| {
            // Clone the row for insertion
            var insert_values = try self.allocator.alloc(storage.Value, row.values.len);
            for (row.values, 0..) |value, i| {
                insert_values[i] = try self.cloneValue(value);
            }
            try new_table.insert(storage.Row{ .values = insert_values });
        }

        result.affected_rows = updated_count;
    }

    /// Execute delete
    fn executeDelete(self: *Self, delete: *planner.DeleteStep, result: *ExecutionResult) !void {
        const table = self.connection.storage_engine.getTable(delete.table_name) orelse {
            return error.TableNotFound;
        };

        // Get all current rows
        const all_rows = try table.select(self.allocator);
        defer {
            for (all_rows) |row| {
                for (row.values) |value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(row.values);
            }
            self.allocator.free(all_rows);
        }

        var deleted_count: u32 = 0;
        var surviving_rows = std.ArrayList(storage.Row).init(self.allocator);
        defer {
            for (surviving_rows.items) |row| {
                for (row.values) |value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(row.values);
            }
            surviving_rows.deinit();
        }

        for (all_rows) |row| {
            // Check if row matches delete condition
            var should_delete = true;
            if (delete.condition) |condition| {
                should_delete = try self.evaluateCondition(&condition, &row);
            }

            if (should_delete) {
                deleted_count += 1;
            } else {
                // Keep this row - clone it for the surviving rows
                var cloned_values = try self.allocator.alloc(storage.Value, row.values.len);
                for (row.values, 0..) |value, i| {
                    cloned_values[i] = try self.cloneValue(value);
                }
                try surviving_rows.append(storage.Row{ .values = cloned_values });
            }
        }

        // Replace the table data with surviving rows
        if (deleted_count > 0) {
            const table_name = try self.allocator.dupe(u8, delete.table_name);
            defer self.allocator.free(table_name);

            // Get table schema
            const schema = table.schema;

            // Drop and recreate table with remaining data
            try self.connection.storage_engine.dropTable(delete.table_name);
            try self.connection.storage_engine.createTable(table_name, schema);

            // Reinsert surviving rows
            const new_table = self.connection.storage_engine.getTable(delete.table_name).?;
            for (surviving_rows.items) |row| {
                // Clone the row for insertion
                var insert_values = try self.allocator.alloc(storage.Value, row.values.len);
                for (row.values, 0..) |value, i| {
                    insert_values[i] = try self.cloneValue(value);
                }
                try new_table.insert(storage.Row{ .values = insert_values });
            }
        }

        result.affected_rows = deleted_count;
    }

    /// Evaluate a condition against a row
    fn evaluateCondition(self: *Self, condition: *const ast.Condition, row: *const storage.Row) !bool {
        return switch (condition.*) {
            .Comparison => |*comp| try self.evaluateComparison(comp, row),
            .Logical => |*logical| {
                const left_result = try self.evaluateCondition(logical.left, row);
                const right_result = try self.evaluateCondition(logical.right, row);

                return switch (logical.operator) {
                    .And => left_result and right_result,
                    .Or => left_result or right_result,
                };
            },
        };
    }

    /// Evaluate a comparison condition
    fn evaluateComparison(self: *Self, comp: *const ast.ComparisonCondition, row: *const storage.Row) !bool {
        const left_value = try self.evaluateExpression(&comp.left, row);
        const right_value = try self.evaluateExpression(&comp.right, row);

        return switch (comp.operator) {
            .Equal => self.compareValues(left_value, right_value) == .eq,
            .NotEqual => self.compareValues(left_value, right_value) != .eq,
            .LessThan => self.compareValues(left_value, right_value) == .lt,
            .LessThanOrEqual => {
                const cmp = self.compareValues(left_value, right_value);
                return cmp == .lt or cmp == .eq;
            },
            .GreaterThan => self.compareValues(left_value, right_value) == .gt,
            .GreaterThanOrEqual => {
                const cmp = self.compareValues(left_value, right_value);
                return cmp == .gt or cmp == .eq;
            },
            .Like => {
                // Simple LIKE implementation (would need pattern matching)
                return self.compareValues(left_value, right_value) == .eq;
            },
            .In => {
                // Simple IN implementation
                return self.compareValues(left_value, right_value) == .eq;
            },
        };
    }

    /// Evaluate an expression against a row
    fn evaluateExpression(self: *Self, expression: *const ast.Expression, row: *const storage.Row) !storage.Value {
        return switch (expression.*) {
            .Column => |col_name| {
                // For now, just return the first value (would need column mapping)
                _ = col_name;
                if (row.values.len > 0) {
                    return row.values[0];
                } else {
                    return storage.Value.Null;
                }
            },
            .Literal => |value| {
                return switch (value) {
                    .Integer => |i| storage.Value{ .Integer = i },
                    .Text => |t| storage.Value{ .Text = try self.allocator.dupe(u8, t) },
                    .Real => |r| storage.Value{ .Real = r },
                    .Blob => |b| storage.Value{ .Blob = try self.allocator.dupe(u8, b) },
                    .Null => storage.Value.Null,
                };
            },
        };
    }

    /// Compare two values
    fn compareValues(self: *Self, left: storage.Value, right: storage.Value) std.math.Order {
        _ = self; // Not needed for value comparison

        return switch (left) {
            .Integer => |l| switch (right) {
                .Integer => |r| std.math.order(l, r),
                .Real => |r| std.math.order(@as(f64, @floatFromInt(l)), r),
                else => .gt, // Non-null values are greater than null
            },
            .Real => |l| switch (right) {
                .Integer => |r| std.math.order(l, @as(f64, @floatFromInt(r))),
                .Real => |r| std.math.order(l, r),
                else => .gt,
            },
            .Text => |l| switch (right) {
                .Text => |r| std.mem.order(u8, l, r),
                else => .gt,
            },
            .Blob => |l| switch (right) {
                .Blob => |r| std.mem.order(u8, l, r),
                else => .gt,
            },
            .Null => switch (right) {
                .Null => .eq,
                else => .lt,
            },
        };
    }
};

/// Result of query execution
pub const ExecutionResult = struct {
    rows: std.ArrayList(storage.Row),
    affected_rows: u32,

    pub fn deinit(self: *ExecutionResult, allocator: std.mem.Allocator) void {
        for (self.rows.items) |row| {
            for (row.values) |value| {
                value.deinit(allocator);
            }
            allocator.free(row.values);
        }
        self.rows.deinit();
    }

    /// Execute nested loop join (simple but works for all join types)
    fn executeNestedLoopJoin(self: *Self, join: *planner.NestedLoopJoinStep, result: *ExecutionResult) !void {
        // Get tables
        const left_table = self.connection.storage_engine.getTable(join.left_table) orelse {
            return error.TableNotFound;
        };
        const right_table = self.connection.storage_engine.getTable(join.right_table) orelse {
            return error.TableNotFound;
        };

        // Get all rows from both tables
        const left_rows = try left_table.select(self.allocator);
        defer {
            for (left_rows) |row| {
                for (row.values) |value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(row.values);
            }
            self.allocator.free(left_rows);
        }

        const right_rows = try right_table.select(self.allocator);
        defer {
            for (right_rows) |row| {
                for (row.values) |value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(row.values);
            }
            self.allocator.free(right_rows);
        }

        // Perform join logic based on join type
        for (left_rows) |left_row| {
            var matched = false;
            
            for (right_rows) |right_row| {
                // Create combined row for condition evaluation
                const combined_row = try self.combineRows(&left_row, &right_row);
                defer {
                    for (combined_row.values) |value| {
                        value.deinit(self.allocator);
                    }
                    self.allocator.free(combined_row.values);
                }

                // Check join condition
                if (try self.evaluateCondition(&join.condition, &combined_row)) {
                    matched = true;
                    // Add the combined row to results
                    const final_row = try self.combineRows(&left_row, &right_row);
                    try result.rows.append(final_row);
                }
            }

            // Handle LEFT JOIN case where no match found
            if (!matched and join.join_type == .Left) {
                const null_right_row = try self.createNullRow(right_rows[0].values.len);
                defer {
                    for (null_right_row.values) |value| {
                        value.deinit(self.allocator);
                    }
                    self.allocator.free(null_right_row.values);
                }
                
                const final_row = try self.combineRows(&left_row, &null_right_row);
                try result.rows.append(final_row);
            }
        }

        // Handle RIGHT JOIN - iterate from right side
        if (join.join_type == .Right or join.join_type == .Full) {
            for (right_rows) |right_row| {
                var matched = false;
                
                for (left_rows) |left_row| {
                    const combined_row = try self.combineRows(&left_row, &right_row);
                    defer {
                        for (combined_row.values) |value| {
                            value.deinit(self.allocator);
                        }
                        self.allocator.free(combined_row.values);
                    }

                    if (try self.evaluateCondition(&join.condition, &combined_row)) {
                        matched = true;
                        break; // We already added this in the LEFT side iteration for FULL
                    }
                }

                // Add unmatched RIGHT rows for RIGHT and FULL joins
                if (!matched and (join.join_type == .Right or join.join_type == .Full)) {
                    const null_left_row = try self.createNullRow(left_rows[0].values.len);
                    defer {
                        for (null_left_row.values) |value| {
                            value.deinit(self.allocator);
                        }
                        self.allocator.free(null_left_row.values);
                    }
                    
                    const final_row = try self.combineRows(&null_left_row, &right_row);
                    try result.rows.append(final_row);
                }
            }
        }
    }

    /// Execute hash join (optimized for equi-joins)
    fn executeHashJoin(self: *Self, join: *planner.HashJoinStep, result: *ExecutionResult) !void {
        // Get tables
        const left_table = self.connection.storage_engine.getTable(join.left_table) orelse {
            return error.TableNotFound;
        };
        const right_table = self.connection.storage_engine.getTable(join.right_table) orelse {
            return error.TableNotFound;
        };

        // Get all rows from both tables
        const left_rows = try left_table.select(self.allocator);
        defer {
            for (left_rows) |row| {
                for (row.values) |value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(row.values);
            }
            self.allocator.free(left_rows);
        }

        const right_rows = try right_table.select(self.allocator);
        defer {
            for (right_rows) |row| {
                for (row.values) |value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(row.values);
            }
            self.allocator.free(right_rows);
        }

        // Build hash table from smaller table (right table for now)
        var hash_map = std.HashMap(u64, std.ArrayList(storage.Row), std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage).init(self.allocator);
        defer {
            var iterator = hash_map.iterator();
            while (iterator.next()) |entry| {
                for (entry.value_ptr.items) |row| {
                    for (row.values) |value| {
                        value.deinit(self.allocator);
                    }
                    self.allocator.free(row.values);
                }
                entry.value_ptr.deinit();
            }
            hash_map.deinit();
        }

        // TODO: For now, fall back to nested loop join
        // Hash join implementation requires column index resolution
        // which needs schema information
        return self.executeNestedLoopJoin(&planner.NestedLoopJoinStep{
            .join_type = join.join_type,
            .left_table = join.left_table,
            .right_table = join.right_table,
            .condition = join.condition,
        }, result);
    }

    /// Combine two rows into a single row
    fn combineRows(self: *Self, left_row: *const storage.Row, right_row: *const storage.Row) !storage.Row {
        const total_columns = left_row.values.len + right_row.values.len;
        var combined_values = try self.allocator.alloc(storage.Value, total_columns);
        
        // Copy left row values
        for (left_row.values, 0..) |value, i| {
            combined_values[i] = try self.cloneValue(value);
        }
        
        // Copy right row values
        for (right_row.values, 0..) |value, i| {
            combined_values[left_row.values.len + i] = try self.cloneValue(value);
        }
        
        return storage.Row{ .values = combined_values };
    }

    /// Create a row with all NULL values
    fn createNullRow(self: *Self, column_count: usize) !storage.Row {
        var null_values = try self.allocator.alloc(storage.Value, column_count);
        for (null_values) |*value| {
            value.* = storage.Value.Null;
        }
        return storage.Row{ .values = null_values };
    }
};

/// Execute a parsed statement (convenience function)
pub fn execute(connection: *db.Connection, parsed: *const ast.Statement) !void {
    var vm = VirtualMachine.init(connection.allocator, connection);

    var query_planner = planner.Planner.init(connection.allocator);
    var plan = try query_planner.plan(parsed);
    defer plan.deinit();

    var result = try vm.execute(&plan);
    defer result.deinit(connection.allocator);

    // Print results based on statement type
    switch (parsed.*) {
        .Select => {
            std.debug.print("┌─ Query Results ─┐\n", .{});
            if (result.rows.items.len == 0) {
                std.debug.print("│ No rows found   │\n", .{});
            } else {
                for (result.rows.items, 0..) |row, i| {
                    std.debug.print("│ Row {d}: ", .{i + 1});
                    for (row.values, 0..) |value, j| {
                        if (j > 0) std.debug.print(", ", .{});
                        switch (value) {
                            .Integer => |int| std.debug.print("{d}", .{int}),
                            .Text => |text| std.debug.print("'{s}'", .{text}),
                            .Real => |real| std.debug.print("{d:.2}", .{real}),
                            .Null => std.debug.print("NULL", .{}),
                            .Blob => std.debug.print("<blob>", .{}),
                        }
                    }
                    std.debug.print(" │\n", .{});
                }
            }
            std.debug.print("└─ {d} row(s) ─────┘\n", .{result.rows.items.len});
        },
        else => {
            std.debug.print("✅ Statement executed successfully. Affected rows: {d}\n", .{result.affected_rows});
        },
    }
}

test "vm creation" {
    try std.testing.expect(true); // Placeholder
}
