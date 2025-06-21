const std = @import("std");
const ast = @import("../parser/ast.zig");
const storage = @import("../db/storage.zig");

/// Query execution planner
pub const Planner = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize planner
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Create execution plan for a statement
    pub fn plan(self: *Self, statement: *const ast.Statement) !ExecutionPlan {
        return switch (statement.*) {
            .Select => |*select| try self.planSelect(select),
            .Insert => |*insert| try self.planInsert(insert),
            .CreateTable => |*create| try self.planCreateTable(create),
            .Update => |*update| try self.planUpdate(update),
            .Delete => |*delete| try self.planDelete(delete),
        };
    }

    /// Plan SELECT statement execution
    fn planSelect(self: *Self, select: *const ast.SelectStatement) !ExecutionPlan {
        var steps = std.ArrayList(ExecutionStep).init(self.allocator);

        // Table scan step
        try steps.append(ExecutionStep{
            .TableScan = TableScanStep{
                .table_name = try self.allocator.dupe(u8, select.table),
            },
        });

        // Filter step (WHERE clause)
        if (select.where_clause) |where_clause| {
            try steps.append(ExecutionStep{
                .Filter = FilterStep{
                    .condition = try self.cloneCondition(&where_clause.condition),
                },
            });
        }

        // Projection step (SELECT columns)
        var columns = std.ArrayList([]const u8).init(self.allocator);
        for (select.columns) |column| {
            try columns.append(try self.allocator.dupe(u8, column.name));
        }

        try steps.append(ExecutionStep{
            .Project = ProjectStep{
                .columns = try columns.toOwnedSlice(),
            },
        });

        // Limit step
        if (select.limit) |limit| {
            try steps.append(ExecutionStep{
                .Limit = LimitStep{
                    .count = limit,
                    .offset = select.offset orelse 0,
                },
            });
        }

        return ExecutionPlan{
            .steps = try steps.toOwnedSlice(),
            .allocator = self.allocator,
        };
    }

    /// Plan INSERT statement execution
    fn planInsert(self: *Self, insert: *const ast.InsertStatement) !ExecutionPlan {
        var steps = std.ArrayList(ExecutionStep).init(self.allocator);

        // Clone columns if provided
        var columns: ?[][]const u8 = null;
        if (insert.columns) |cols| {
            var cloned_cols = std.ArrayList([]const u8).init(self.allocator);
            for (cols) |col| {
                try cloned_cols.append(try self.allocator.dupe(u8, col));
            }
            columns = try cloned_cols.toOwnedSlice();
        }

        // Clone values
        var values = std.ArrayList([]storage.Value).init(self.allocator);
        for (insert.values) |row| {
            var cloned_row = std.ArrayList(storage.Value).init(self.allocator);
            for (row) |value| {
                try cloned_row.append(try self.cloneValue(value));
            }
            try values.append(try cloned_row.toOwnedSlice());
        }

        try steps.append(ExecutionStep{
            .Insert = InsertStep{
                .table_name = try self.allocator.dupe(u8, insert.table),
                .columns = columns,
                .values = try values.toOwnedSlice(),
            },
        });

        return ExecutionPlan{
            .steps = try steps.toOwnedSlice(),
            .allocator = self.allocator,
        };
    }

    /// Plan CREATE TABLE statement execution
    fn planCreateTable(self: *Self, create: *const ast.CreateTableStatement) !ExecutionPlan {
        var steps = std.ArrayList(ExecutionStep).init(self.allocator);

        // Clone column definitions
        var columns = std.ArrayList(storage.Column).init(self.allocator);
        for (create.columns) |col_def| {
            try columns.append(storage.Column{
                .name = try self.allocator.dupe(u8, col_def.name),
                .data_type = switch (col_def.data_type) {
                    .Integer => storage.DataType.Integer,
                    .Text => storage.DataType.Text,
                    .Real => storage.DataType.Real,
                    .Blob => storage.DataType.Blob,
                },
                .is_primary_key = blk: {
                    for (col_def.constraints) |constraint| {
                        if (constraint == .PrimaryKey) break :blk true;
                    }
                    break :blk false;
                },
                .is_nullable = blk: {
                    for (col_def.constraints) |constraint| {
                        if (constraint == .NotNull) break :blk false;
                    }
                    break :blk true;
                },
            });
        }

        try steps.append(ExecutionStep{
            .CreateTable = CreateTableStep{
                .table_name = try self.allocator.dupe(u8, create.table_name),
                .columns = try columns.toOwnedSlice(),
                .if_not_exists = create.if_not_exists,
            },
        });

        return ExecutionPlan{
            .steps = try steps.toOwnedSlice(),
            .allocator = self.allocator,
        };
    }

    /// Plan UPDATE statement execution
    fn planUpdate(self: *Self, update: *const ast.UpdateStatement) !ExecutionPlan {
        var steps = std.ArrayList(ExecutionStep).init(self.allocator);

        // Clone assignments
        var assignments = std.ArrayList(UpdateAssignment).init(self.allocator);
        for (update.assignments) |assignment| {
            try assignments.append(UpdateAssignment{
                .column = try self.allocator.dupe(u8, assignment.column),
                .value = try self.cloneValue(assignment.value),
            });
        }

        var condition: ?ast.Condition = null;
        if (update.where_clause) |where_clause| {
            condition = try self.cloneCondition(&where_clause.condition);
        }

        try steps.append(ExecutionStep{
            .Update = UpdateStep{
                .table_name = try self.allocator.dupe(u8, update.table),
                .assignments = try assignments.toOwnedSlice(),
                .condition = condition,
            },
        });

        return ExecutionPlan{
            .steps = try steps.toOwnedSlice(),
            .allocator = self.allocator,
        };
    }

    /// Plan DELETE statement execution
    fn planDelete(self: *Self, delete: *const ast.DeleteStatement) !ExecutionPlan {
        var steps = std.ArrayList(ExecutionStep).init(self.allocator);

        var condition: ?ast.Condition = null;
        if (delete.where_clause) |where_clause| {
            condition = try self.cloneCondition(&where_clause.condition);
        }

        try steps.append(ExecutionStep{
            .Delete = DeleteStep{
                .table_name = try self.allocator.dupe(u8, delete.table),
                .condition = condition,
            },
        });

        return ExecutionPlan{
            .steps = try steps.toOwnedSlice(),
            .allocator = self.allocator,
        };
    }

    /// Clone a condition (deep copy)
    fn cloneCondition(self: *Self, condition: *const ast.Condition) !ast.Condition {
        return switch (condition.*) {
            .Comparison => |*comp| ast.Condition{
                .Comparison = ast.ComparisonCondition{
                    .left = try self.cloneExpression(&comp.left),
                    .operator = comp.operator,
                    .right = try self.cloneExpression(&comp.right),
                },
            },
            .Logical => |*logical| {
                const left_ptr = try self.allocator.create(ast.Condition);
                left_ptr.* = try self.cloneCondition(logical.left);

                const right_ptr = try self.allocator.create(ast.Condition);
                right_ptr.* = try self.cloneCondition(logical.right);

                return ast.Condition{
                    .Logical = ast.LogicalCondition{
                        .left = left_ptr,
                        .operator = logical.operator,
                        .right = right_ptr,
                    },
                };
            },
        };
    }

    /// Clone an expression
    fn cloneExpression(self: *Self, expression: *const ast.Expression) !ast.Expression {
        return switch (expression.*) {
            .Column => |col| ast.Expression{ .Column = try self.allocator.dupe(u8, col) },
            .Literal => |value| ast.Expression{ .Literal = try self.cloneAstValue(value) },
        };
    }

    /// Clone a value
    fn cloneValue(self: *Self, value: ast.Value) !storage.Value {
        return switch (value) {
            .Integer => |i| storage.Value{ .Integer = i },
            .Text => |t| storage.Value{ .Text = try self.allocator.dupe(u8, t) },
            .Real => |r| storage.Value{ .Real = r },
            .Blob => |b| storage.Value{ .Blob = try self.allocator.dupe(u8, b) },
            .Null => storage.Value.Null,
        };
    }

    /// Clone an AST value (different from storage value)
    fn cloneAstValue(self: *Self, value: ast.Value) !ast.Value {
        return switch (value) {
            .Integer => |i| ast.Value{ .Integer = i },
            .Text => |t| ast.Value{ .Text = try self.allocator.dupe(u8, t) },
            .Real => |r| ast.Value{ .Real = r },
            .Blob => |b| ast.Value{ .Blob = try self.allocator.dupe(u8, b) },
            .Null => ast.Value.Null,
        };
    }
};

/// Execution plan containing steps to execute
pub const ExecutionPlan = struct {
    steps: []ExecutionStep,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ExecutionPlan) void {
        for (self.steps) |*step| {
            step.deinit(self.allocator);
        }
        self.allocator.free(self.steps);
    }
};

/// Individual execution steps
pub const ExecutionStep = union(enum) {
    TableScan: TableScanStep,
    Filter: FilterStep,
    Project: ProjectStep,
    Limit: LimitStep,
    Insert: InsertStep,
    CreateTable: CreateTableStep,
    Update: UpdateStep,
    Delete: DeleteStep,

    pub fn deinit(self: *ExecutionStep, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .TableScan => |*step| step.deinit(allocator),
            .Filter => |*step| step.deinit(allocator),
            .Project => |*step| step.deinit(allocator),
            .Limit => {},
            .Insert => |*step| step.deinit(allocator),
            .CreateTable => |*step| step.deinit(allocator),
            .Update => |*step| step.deinit(allocator),
            .Delete => |*step| step.deinit(allocator),
        }
    }
};

/// Table scan step
pub const TableScanStep = struct {
    table_name: []const u8,

    pub fn deinit(self: *TableScanStep, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
    }
};

/// Filter step (WHERE clause)
pub const FilterStep = struct {
    condition: ast.Condition,

    pub fn deinit(self: *FilterStep, allocator: std.mem.Allocator) void {
        self.condition.deinit(allocator);
    }
};

/// Projection step (SELECT columns)
pub const ProjectStep = struct {
    columns: [][]const u8,

    pub fn deinit(self: *ProjectStep, allocator: std.mem.Allocator) void {
        for (self.columns) |column| {
            allocator.free(column);
        }
        allocator.free(self.columns);
    }
};

/// Limit step
pub const LimitStep = struct {
    count: u32,
    offset: u32,
};

/// Insert step
pub const InsertStep = struct {
    table_name: []const u8,
    columns: ?[][]const u8,
    values: [][]storage.Value,

    pub fn deinit(self: *InsertStep, allocator: std.mem.Allocator) void {
        // Free table name
        allocator.free(self.table_name);

        // Free columns if they exist
        if (self.columns) |cols| {
            for (cols) |col| {
                allocator.free(col);
            }
            allocator.free(cols);
        }

        // Free values properly
        for (self.values) |row| {
            // Each row is an owned slice of Values
            for (row) |value| {
                value.deinit(allocator);
            }
            // Free the row array itself
            allocator.free(row);
        }
        // Free the values array
        allocator.free(self.values);
    }
};

/// Create table step
pub const CreateTableStep = struct {
    table_name: []const u8,
    columns: []storage.Column,
    if_not_exists: bool,

    pub fn deinit(self: *CreateTableStep, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
        for (self.columns) |column| {
            allocator.free(column.name);
        }
        allocator.free(self.columns);
    }
};

/// Update step
pub const UpdateStep = struct {
    table_name: []const u8,
    assignments: []UpdateAssignment,
    condition: ?ast.Condition,

    pub fn deinit(self: *UpdateStep, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
        for (self.assignments) |assignment| {
            allocator.free(assignment.column);
            assignment.value.deinit(allocator);
        }
        allocator.free(self.assignments);
        if (self.condition) |*cond| {
            cond.deinit(allocator);
        }
    }
};

/// Delete step
pub const DeleteStep = struct {
    table_name: []const u8,
    condition: ?ast.Condition,

    pub fn deinit(self: *DeleteStep, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
        if (self.condition) |*cond| {
            cond.deinit(allocator);
        }
    }
};

/// Update assignment
pub const UpdateAssignment = struct {
    column: []const u8,
    value: storage.Value,
};

test "planner creation" {
    const allocator = std.testing.allocator;
    const planner = Planner.init(allocator);
    _ = planner; // Suppress unused variable warning
    try std.testing.expect(true);
}
