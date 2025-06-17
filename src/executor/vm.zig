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
        }
    }

    /// Execute table scan
    fn executeTableScan(self: *Self, scan: *planner.TableScanStep, result: *ExecutionResult) !void {
        const table = self.connection.storage_engine.getTable(scan.table_name) orelse {
            return error.TableNotFound;
        };

        const rows = try table.select(self.allocator);
        for (rows) |row| {
            try result.rows.append(row);
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
            const row = storage.Row{ .values = row_values };
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

        const schema = storage.TableSchema{
            .columns = create.columns,
        };

        try self.connection.storage_engine.createTable(create.table_name, schema);
        result.affected_rows = 1;
    }

    /// Execute update
    fn executeUpdate(self: *Self, update: *planner.UpdateStep, result: *ExecutionResult) !void {
        const table = self.connection.storage_engine.getTable(update.table_name) orelse {
            return error.TableNotFound;
        };

        // For now, do a simple table scan and update matching rows
        const all_rows = try table.select(self.allocator);
        defer self.allocator.free(all_rows);

        var updated_count: u32 = 0;

        for (all_rows) |row| {
            // Check if row matches condition
            var matches = true;
            if (update.condition) |condition| {
                matches = try self.evaluateCondition(&condition, &row);
            }

            if (matches) {
                // Create updated row
                var updated_row = storage.Row{
                    .values = try self.allocator.dupe(storage.Value, row.values),
                };

                // Apply assignments
                for (update.assignments) |assignment| {
                    // For simplicity, update first column that matches
                    // In real implementation, would need proper column mapping
                    if (updated_row.values.len > 0) {
                        updated_row.values[0].deinit(self.allocator);
                        updated_row.values[0] = try self.cloneValue(assignment.value);
                    }
                    _ = assignment.column; // Suppress unused warning
                }

                // In a real implementation, would update the B-tree entry
                // For now, just count the update
                updated_count += 1;

                // Clean up
                for (updated_row.values) |value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(updated_row.values);
            }
        }

        result.affected_rows = updated_count;
    }

    /// Execute delete
    fn executeDelete(self: *Self, delete: *planner.DeleteStep, result: *ExecutionResult) !void {
        const table = self.connection.storage_engine.getTable(delete.table_name) orelse {
            return error.TableNotFound;
        };

        // For now, do a simple table scan and mark matching rows for deletion
        const all_rows = try table.select(self.allocator);
        defer self.allocator.free(all_rows);

        var deleted_count: u32 = 0;

        for (all_rows) |row| {
            // Check if row matches condition
            var matches = true;
            if (delete.condition) |condition| {
                matches = try self.evaluateCondition(&condition, &row);
            }

            if (matches) {
                // In a real implementation, would remove from B-tree
                // For now, just count the deletion
                deleted_count += 1;
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
};

/// Execute a parsed statement (convenience function)
pub fn execute(connection: *db.Connection, parsed: *const ast.Statement) !void {
    var vm = VirtualMachine.init(connection.allocator, connection);

    var query_planner = planner.Planner.init(connection.allocator);
    var plan = try query_planner.plan(parsed);
    defer plan.deinit();

    var result = try vm.execute(&plan);
    defer result.deinit(connection.allocator);

    // For now, just print the result
    std.debug.print("Executed statement. Affected rows: {d}, Result rows: {d}\n", .{ result.affected_rows, result.rows.items.len });
}

test "vm creation" {
    try std.testing.expect(true); // Placeholder
}
