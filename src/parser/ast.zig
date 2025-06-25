const std = @import("std");

/// Abstract Syntax Tree for SQL statements
pub const Statement = union(enum) {
    Select: SelectStatement,
    Insert: InsertStatement,
    CreateTable: CreateTableStatement,
    Update: UpdateStatement,
    Delete: DeleteStatement,

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Select => |*stmt| stmt.deinit(allocator),
            .Insert => |*stmt| stmt.deinit(allocator),
            .CreateTable => |*stmt| stmt.deinit(allocator),
            .Update => |*stmt| stmt.deinit(allocator),
            .Delete => |*stmt| stmt.deinit(allocator),
        }
    }
};

/// SELECT statement AST
pub const SelectStatement = struct {
    columns: []Column,
    table: []const u8,
    joins: []JoinClause,
    where_clause: ?WhereClause,
    group_by: ?[][]const u8,
    having: ?WhereClause,
    order_by: ?[]OrderByClause,
    limit: ?u32,
    offset: ?u32,

    pub fn deinit(self: *SelectStatement, allocator: std.mem.Allocator) void {
        for (self.columns) |*column| {
            column.expression.deinit(allocator);
            if (column.alias) |alias| {
                allocator.free(alias);
            }
        }
        allocator.free(self.columns);
        allocator.free(self.table);

        for (self.joins) |*join| {
            allocator.free(join.table);
            join.condition.deinit(allocator);
        }
        allocator.free(self.joins);

        if (self.where_clause) |*where| {
            where.deinit(allocator);
        }

        if (self.group_by) |group_by| {
            for (group_by) |col| {
                allocator.free(col);
            }
            allocator.free(group_by);
        }

        if (self.having) |*having| {
            having.deinit(allocator);
        }

        if (self.order_by) |order_by| {
            for (order_by) |clause| {
                allocator.free(clause.column);
            }
            allocator.free(order_by);
        }
    }
};

/// INSERT statement AST
pub const InsertStatement = struct {
    table: []const u8,
    columns: ?[][]const u8,
    values: [][]Value,

    pub fn deinit(self: *InsertStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.table);
        if (self.columns) |cols| {
            for (cols) |col| {
                allocator.free(col);
            }
            allocator.free(cols);
        }
        for (self.values) |row| {
            for (row) |value| {
                value.deinit(allocator);
            }
            allocator.free(row);
        }
        allocator.free(self.values);
    }
};

/// CREATE TABLE statement AST
pub const CreateTableStatement = struct {
    table_name: []const u8,
    columns: []ColumnDefinition,
    if_not_exists: bool,

    pub fn deinit(self: *CreateTableStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
        for (self.columns) |column| {
            allocator.free(column.name);
        }
        allocator.free(self.columns);
    }
};

/// UPDATE statement AST
pub const UpdateStatement = struct {
    table: []const u8,
    assignments: []Assignment,
    where_clause: ?WhereClause,

    pub fn deinit(self: *UpdateStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.table);
        for (self.assignments) |assignment| {
            allocator.free(assignment.column);
            assignment.value.deinit(allocator);
        }
        allocator.free(self.assignments);
        if (self.where_clause) |*where| {
            where.deinit(allocator);
        }
    }
};

/// DELETE statement AST
pub const DeleteStatement = struct {
    table: []const u8,
    where_clause: ?WhereClause,

    pub fn deinit(self: *DeleteStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.table);
        if (self.where_clause) |*where| {
            where.deinit(allocator);
        }
    }
};

/// Column in SELECT statement
pub const Column = struct {
    name: []const u8,
    expression: ColumnExpression,
    alias: ?[]const u8,
};

/// Column expression (can be a simple column or aggregate function)
pub const ColumnExpression = union(enum) {
    Simple: []const u8, // Simple column name
    Aggregate: AggregateFunction,
    
    pub fn deinit(self: *ColumnExpression, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Simple => |name| allocator.free(name),
            .Aggregate => |*agg| agg.deinit(allocator),
        }
    }
};

/// Aggregate function
pub const AggregateFunction = struct {
    function_type: AggregateFunctionType,
    column: ?[]const u8, // NULL for COUNT(*)
    
    pub fn deinit(self: *AggregateFunction, allocator: std.mem.Allocator) void {
        if (self.column) |col| {
            allocator.free(col);
        }
    }
};

/// Aggregate function types
pub const AggregateFunctionType = enum {
    Count,
    Sum,
    Avg,
    Min,
    Max,
};

/// Column definition in CREATE TABLE
pub const ColumnDefinition = struct {
    name: []const u8,
    data_type: DataType,
    constraints: []ColumnConstraint,
};

/// Data types
pub const DataType = enum {
    Integer,
    Text,
    Real,
    Blob,
};

/// Column constraints
pub const ColumnConstraint = enum {
    PrimaryKey,
    NotNull,
    Unique,
    AutoIncrement,
};

/// WHERE clause
pub const WhereClause = struct {
    condition: Condition,

    pub fn deinit(self: *WhereClause, allocator: std.mem.Allocator) void {
        self.condition.deinit(allocator);
    }
};

/// Conditions in WHERE clauses
pub const Condition = union(enum) {
    Comparison: ComparisonCondition,
    Logical: LogicalCondition,

    pub fn deinit(self: *Condition, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Comparison => |*comp| comp.deinit(allocator),
            .Logical => |*logical| logical.deinit(allocator),
        }
    }
};

/// Comparison condition (e.g., column = value)
pub const ComparisonCondition = struct {
    left: Expression,
    operator: ComparisonOperator,
    right: Expression,

    pub fn deinit(self: *ComparisonCondition, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        self.right.deinit(allocator);
    }
};

/// Logical condition (AND, OR)
pub const LogicalCondition = struct {
    left: *Condition,
    operator: LogicalOperator,
    right: *Condition,

    pub fn deinit(self: *LogicalCondition, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        self.right.deinit(allocator);
        allocator.destroy(self.left);
        allocator.destroy(self.right);
    }
};

/// Comparison operators
pub const ComparisonOperator = enum {
    Equal,
    NotEqual,
    LessThan,
    LessThanOrEqual,
    GreaterThan,
    GreaterThanOrEqual,
    Like,
    In,
};

/// Logical operators
pub const LogicalOperator = enum {
    And,
    Or,
};

/// Expression (column reference or literal value)
pub const Expression = union(enum) {
    Column: []const u8,
    Literal: Value,

    pub fn deinit(self: *Expression, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Column => |col| allocator.free(col),
            .Literal => |value| value.deinit(allocator),
        }
    }
};

/// Assignment in UPDATE statement
pub const Assignment = struct {
    column: []const u8,
    value: Value,
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

/// JOIN clause
pub const JoinClause = struct {
    join_type: JoinType,
    table: []const u8,
    condition: Condition,
};

/// JOIN types
pub const JoinType = enum {
    Inner,
    Left,
    Right,
    Full,
};

/// ORDER BY clause
pub const OrderByClause = struct {
    column: []const u8,
    direction: SortDirection,
};

/// Sort direction
pub const SortDirection = enum {
    Asc,
    Desc,
};

test "ast creation" {
    try std.testing.expect(true); // Placeholder
}
