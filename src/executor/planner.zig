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

        // JOIN steps
        for (select.joins) |join| {
            const join_step = try self.planJoin(select.table, &join);
            try steps.append(join_step);
        }

        // Filter step (WHERE clause)
        if (select.where_clause) |where_clause| {
            try steps.append(ExecutionStep{
                .Filter = FilterStep{
                    .condition = try self.cloneCondition(&where_clause.condition),
                },
            });
        }

        // Check if we have aggregate functions
        const has_aggregates = self.hasAggregates(select.columns);
        
        if (has_aggregates) {
            // Extract aggregate operations
            var aggregates = std.ArrayList(AggregateOperation).init(self.allocator);
            for (select.columns) |column| {
                if (column.expression == .Aggregate) {
                    try aggregates.append(AggregateOperation{
                        .function_type = column.expression.Aggregate.function_type,
                        .column = if (column.expression.Aggregate.column) |col| 
                            try self.allocator.dupe(u8, col) 
                        else 
                            null,
                        .alias = if (column.alias) |alias| 
                            try self.allocator.dupe(u8, alias) 
                        else 
                            null,
                    });
                }
            }
            
            if (select.group_by) |group_by| {
                // GROUP BY aggregation
                var group_columns = std.ArrayList([]const u8).init(self.allocator);
                for (group_by) |col| {
                    try group_columns.append(try self.allocator.dupe(u8, col));
                }
                
                try steps.append(ExecutionStep{
                    .GroupBy = GroupByStep{
                        .group_columns = try group_columns.toOwnedSlice(),
                        .aggregates = try aggregates.toOwnedSlice(),
                    },
                });
            } else {
                // Simple aggregation (no GROUP BY)
                try steps.append(ExecutionStep{
                    .Aggregate = AggregateStep{
                        .aggregates = try aggregates.toOwnedSlice(),
                    },
                });
            }
        } else {
            // Regular projection step (SELECT columns)
            var columns = std.ArrayList([]const u8).init(self.allocator);
            for (select.columns) |column| {
                switch (column.expression) {
                    .Simple => |name| try columns.append(try self.allocator.dupe(u8, name)),
                    .Aggregate => {
                        // This shouldn't happen if has_aggregates was false
                        return error.UnexpectedAggregate;
                    },
                }
            }

            try steps.append(ExecutionStep{
                .Project = ProjectStep{
                    .columns = try columns.toOwnedSlice(),
                },
            });
        }

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

    /// Plan JOIN operation
    fn planJoin(self: *Self, left_table: []const u8, join: *const ast.JoinClause) !ExecutionStep {
        // Try to determine if this is an equi-join for hash join optimization
        const equi_join_info = self.analyzeEquiJoin(&join.condition);
        
        if (equi_join_info) |info| {
            // Use hash join for equi-joins (more efficient for larger datasets)
            return ExecutionStep{
                .HashJoin = HashJoinStep{
                    .join_type = join.join_type,
                    .left_table = try self.allocator.dupe(u8, left_table),
                    .right_table = try self.allocator.dupe(u8, join.table),
                    .left_key_column = try self.allocator.dupe(u8, info.left_column),
                    .right_key_column = try self.allocator.dupe(u8, info.right_column),
                    .condition = try self.cloneCondition(&join.condition),
                },
            };
        } else {
            // Use nested loop join for complex conditions
            return ExecutionStep{
                .NestedLoopJoin = NestedLoopJoinStep{
                    .join_type = join.join_type,
                    .left_table = try self.allocator.dupe(u8, left_table),
                    .right_table = try self.allocator.dupe(u8, join.table),
                    .condition = try self.cloneCondition(&join.condition),
                },
            };
        }
    }

    /// Analyze if condition is an equi-join (column = column)
    fn analyzeEquiJoin(self: *Self, condition: *const ast.Condition) ?EquiJoinInfo {
        _ = self;
        switch (condition.*) {
            .Comparison => |comp| {
                if (comp.operator == .Equal) {
                    // Check if both sides are column references
                    if (comp.left == .Column and comp.right == .Column) {
                        return EquiJoinInfo{
                            .left_column = comp.left.Column,
                            .right_column = comp.right.Column,
                        };
                    }
                }
            },
            .Logical => {
                // For now, don't optimize complex logical conditions
                // Could be enhanced to handle AND of equi-joins
            },
        }
        return null;
    }

    const EquiJoinInfo = struct {
        left_column: []const u8,
        right_column: []const u8,
    };

    /// Check if any columns contain aggregate functions
    fn hasAggregates(self: *Self, columns: []ast.Column) bool {
        _ = self;
        for (columns) |column| {
            if (column.expression == .Aggregate) {
                return true;
            }
        }
        return false;
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
                .default_value = blk: {
                    for (col_def.constraints) |constraint| {
                        if (constraint == .Default) {
                            const default_value = try self.convertAstDefaultToStorage(constraint.Default);
                            break :blk default_value;
                        }
                    }
                    break :blk null;
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
            .Parameter => |param_index| ast.Expression{ .Parameter = param_index },
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
            .Parameter => |param_index| storage.Value{ .Parameter = param_index },
        };
    }
    
    /// Clone a default value (preserving FunctionCall for VM evaluation)
    fn cloneDefaultValue(self: *Self, default_value: ast.DefaultValue) !ast.DefaultValue {
        return switch (default_value) {
            .Literal => |literal| ast.DefaultValue{ .Literal = try self.cloneAstValue(literal) },
            .FunctionCall => |function_call| ast.DefaultValue{ .FunctionCall = try self.cloneFunctionCall(function_call) },
        };
    }
    
    /// Clone a function call
    fn cloneFunctionCall(self: *Self, function_call: ast.FunctionCall) !ast.FunctionCall {
        var cloned_args = try self.allocator.alloc(ast.FunctionArgument, function_call.arguments.len);
        for (function_call.arguments, 0..) |arg, i| {
            cloned_args[i] = try self.cloneFunctionArgument(arg);
        }
        
        return ast.FunctionCall{
            .name = try self.allocator.dupe(u8, function_call.name),
            .arguments = cloned_args,
        };
    }
    
    /// Clone a function argument
    fn cloneFunctionArgument(self: *Self, arg: ast.FunctionArgument) !ast.FunctionArgument {
        return switch (arg) {
            .Literal => |literal| ast.FunctionArgument{ .Literal = try self.cloneAstValue(literal) },
            .Column => |column| ast.FunctionArgument{ .Column = try self.allocator.dupe(u8, column) },
            .Parameter => |param_index| ast.FunctionArgument{ .Parameter = param_index },
        };
    }
    
    /// Convert AST default value to storage default value
    fn convertAstDefaultToStorage(self: *Self, default_value: ast.DefaultValue) !storage.Column.DefaultValue {
        return switch (default_value) {
            .Literal => |literal| {
                const storage_value = try self.cloneValue(literal);
                return storage.Column.DefaultValue{ .Literal = storage_value };
            },
            .FunctionCall => |function_call| {
                const storage_func = try self.convertAstFunctionToStorage(function_call);
                return storage.Column.DefaultValue{ .FunctionCall = storage_func };
            },
        };
    }
    
    /// Convert AST function call to storage function call
    fn convertAstFunctionToStorage(self: *Self, function_call: ast.FunctionCall) !storage.Column.FunctionCall {
        var storage_args = try self.allocator.alloc(storage.Column.FunctionArgument, function_call.arguments.len);
        for (function_call.arguments, 0..) |arg, i| {
            storage_args[i] = try self.convertAstFunctionArgToStorage(arg);
        }
        
        return storage.Column.FunctionCall{
            .name = try self.allocator.dupe(u8, function_call.name),
            .arguments = storage_args,
        };
    }
    
    /// Convert AST function argument to storage function argument
    fn convertAstFunctionArgToStorage(self: *Self, arg: ast.FunctionArgument) !storage.Column.FunctionArgument {
        return switch (arg) {
            .Literal => |literal| {
                const storage_value = try self.cloneValue(literal);
                return storage.Column.FunctionArgument{ .Literal = storage_value };
            },
            .String => |string| {
                // Convert string to Text literal
                const text_value = storage.Value{ .Text = try self.allocator.dupe(u8, string) };
                return storage.Column.FunctionArgument{ .Literal = text_value };
            },
            .Column => |column| {
                return storage.Column.FunctionArgument{ .Column = try self.allocator.dupe(u8, column) };
            },
            .Parameter => |param_index| {
                return storage.Column.FunctionArgument{ .Parameter = param_index };
            },
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
            .Parameter => |param_index| ast.Value{ .Parameter = param_index },
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
    NestedLoopJoin: NestedLoopJoinStep,
    HashJoin: HashJoinStep,
    Aggregate: AggregateStep,
    GroupBy: GroupByStep,

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
            .NestedLoopJoin => |*step| step.deinit(allocator),
            .HashJoin => |*step| step.deinit(allocator),
            .Aggregate => |*step| step.deinit(allocator),
            .GroupBy => |*step| step.deinit(allocator),
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

/// Nested loop join step (for small tables or when no indexes available)
pub const NestedLoopJoinStep = struct {
    join_type: ast.JoinType,
    left_table: []const u8,
    right_table: []const u8,
    condition: ast.Condition,
    
    pub fn deinit(self: *NestedLoopJoinStep, allocator: std.mem.Allocator) void {
        allocator.free(self.left_table);
        allocator.free(self.right_table);
        self.condition.deinit(allocator);
    }
};

/// Hash join step (for larger tables with equi-join conditions)
pub const HashJoinStep = struct {
    join_type: ast.JoinType,
    left_table: []const u8,
    right_table: []const u8,
    left_key_column: []const u8,
    right_key_column: []const u8,
    condition: ast.Condition,
    
    pub fn deinit(self: *HashJoinStep, allocator: std.mem.Allocator) void {
        allocator.free(self.left_table);
        allocator.free(self.right_table);
        allocator.free(self.left_key_column);
        allocator.free(self.right_key_column);
        self.condition.deinit(allocator);
    }
};

/// Aggregate step (for aggregate functions without GROUP BY)
pub const AggregateStep = struct {
    aggregates: []AggregateOperation,
    
    pub fn deinit(self: *AggregateStep, allocator: std.mem.Allocator) void {
        for (self.aggregates) |*agg| {
            agg.deinit(allocator);
        }
        allocator.free(self.aggregates);
    }
};

/// Group by step (for aggregate functions with GROUP BY)
pub const GroupByStep = struct {
    group_columns: [][]const u8,
    aggregates: []AggregateOperation,
    
    pub fn deinit(self: *GroupByStep, allocator: std.mem.Allocator) void {
        for (self.group_columns) |col| {
            allocator.free(col);
        }
        allocator.free(self.group_columns);
        
        for (self.aggregates) |*agg| {
            agg.deinit(allocator);
        }
        allocator.free(self.aggregates);
    }
};

/// Aggregate operation definition
pub const AggregateOperation = struct {
    function_type: ast.AggregateFunctionType,
    column: ?[]const u8, // NULL for COUNT(*)
    alias: ?[]const u8,
    
    pub fn deinit(self: *AggregateOperation, allocator: std.mem.Allocator) void {
        if (self.column) |col| {
            allocator.free(col);
        }
        if (self.alias) |alias| {
            allocator.free(alias);
        }
    }
};

test "planner creation" {
    const allocator = std.testing.allocator;
    const planner = Planner.init(allocator);
    _ = planner; // Suppress unused variable warning
    try std.testing.expect(true);
}
