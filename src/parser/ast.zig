const std = @import("std");

/// Abstract Syntax Tree for SQL statements
pub const Statement = union(enum) {
    Select: SelectStatement,
    Insert: InsertStatement,
    CreateTable: CreateTableStatement,
    Update: UpdateStatement,
    Delete: DeleteStatement,
    BeginTransaction: TransactionStatement,
    Commit: TransactionStatement,
    Rollback: TransactionStatement,
    CreateIndex: CreateIndexStatement,
    DropIndex: DropIndexStatement,
    // PostgreSQL compatibility statements
    With: WithStatement, // Common Table Expressions

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Select => |*stmt| stmt.deinit(allocator),
            .Insert => |*stmt| stmt.deinit(allocator),
            .CreateTable => |*stmt| stmt.deinit(allocator),
            .Update => |*stmt| stmt.deinit(allocator),
            .Delete => |*stmt| stmt.deinit(allocator),
            .BeginTransaction => |*stmt| stmt.deinit(allocator),
            .Commit => |*stmt| stmt.deinit(allocator),
            .Rollback => |*stmt| stmt.deinit(allocator),
            .CreateIndex => |*stmt| stmt.deinit(allocator),
            .DropIndex => |*stmt| stmt.deinit(allocator),
            .With => |*stmt| stmt.deinit(allocator),
        }
    }
};

/// SELECT statement AST
pub const SelectStatement = struct {
    columns: []Column,
    table: ?[]const u8, // Nullable for CTEs that don't reference tables
    joins: []JoinClause,
    where_clause: ?WhereClause,
    group_by: ?[][]const u8,
    having: ?WhereClause,
    order_by: ?[]OrderByClause,
    limit: ?u32,
    offset: ?u32,
    window_definitions: ?[]WindowDefinition, // PostgreSQL window functions

    pub fn deinit(self: *SelectStatement, allocator: std.mem.Allocator) void {
        for (self.columns) |*column| {
            allocator.free(column.name);
            column.expression.deinit(allocator);
            if (column.alias) |alias| {
                allocator.free(alias);
            }
        }
        allocator.free(self.columns);
        
        if (self.table) |table| {
            allocator.free(table);
        }

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
        
        if (self.window_definitions) |windows| {
            for (windows) |*window| {
                window.deinit(allocator);
            }
            allocator.free(windows);
        }
    }
};

/// INSERT statement AST
pub const InsertStatement = struct {
    table: []const u8,
    columns: ?[][]const u8,
    values: [][]Value,
    or_conflict: ?ConflictResolution,

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

/// Conflict resolution for INSERT
pub const ConflictResolution = enum {
    Replace,
    Ignore,
    Abort,
    Fail,
    Rollback,
};

/// CREATE TABLE statement AST
pub const CreateTableStatement = struct {
    table_name: []const u8,
    columns: []ColumnDefinition,
    table_constraints: []TableConstraint,
    if_not_exists: bool,

    pub fn deinit(self: *CreateTableStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
        for (self.columns) |column| {
            allocator.free(column.name);
            for (column.constraints) |constraint| {
                constraint.deinit(allocator);
            }
            allocator.free(column.constraints);
        }
        allocator.free(self.columns);
        
        for (self.table_constraints) |constraint| {
            constraint.deinit(allocator);
        }
        allocator.free(self.table_constraints);
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

/// Column expression (can be a simple column, aggregate function, or window function)
pub const ColumnExpression = union(enum) {
    Simple: []const u8, // Simple column name
    Aggregate: AggregateFunction,
    Window: WindowFunction, // PostgreSQL window functions
    FunctionCall: FunctionCall, // Regular function calls
    
    pub fn deinit(self: *ColumnExpression, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Simple => |name| allocator.free(name),
            .Aggregate => |*agg| agg.deinit(allocator),
            .Window => |*window| window.deinit(allocator),
            .FunctionCall => |*func| func.deinit(allocator),
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
    GroupConcat,
    CountDistinct,
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
    DateTime,
    Timestamp,
    Boolean,
    Date,
    Time,
    Decimal,
    Varchar,
    Char,
    Float,
    Double,
    SmallInt,
    BigInt,
    // PostgreSQL compatibility types
    JSON,
    JSONB,
    UUID,
    Array,
    TimestampTZ,
    Interval,
    Numeric,
};

/// Default value for column constraints
pub const DefaultValue = union(enum) {
    Literal: Value,
    FunctionCall: FunctionCall,
    
    pub fn deinit(self: DefaultValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .Literal => |value| value.deinit(allocator),
            .FunctionCall => |func| func.deinit(allocator),
        }
    }
};

/// Function call expression
pub const FunctionCall = struct {
    name: []const u8,
    arguments: []FunctionArgument,
    
    pub fn deinit(self: FunctionCall, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.arguments) |arg| {
            arg.deinit(allocator);
        }
        allocator.free(self.arguments);
    }
};

/// Function call argument
pub const FunctionArgument = union(enum) {
    Literal: Value,
    String: []const u8,
    Column: []const u8,
    Parameter: u32,
    
    pub fn deinit(self: FunctionArgument, allocator: std.mem.Allocator) void {
        switch (self) {
            .Literal => |value| value.deinit(allocator),
            .String => |str| allocator.free(str),
            .Column => |col| allocator.free(col),
            .Parameter => {},
        }
    }
};

/// Column constraints
pub const ColumnConstraint = union(enum) {
    PrimaryKey,
    NotNull,
    Unique,
    AutoIncrement,
    Default: DefaultValue,
    ForeignKey: ForeignKeyConstraint,
    Check: CheckConstraint,
    
    pub fn deinit(self: ColumnConstraint, allocator: std.mem.Allocator) void {
        switch (self) {
            .Default => |default| default.deinit(allocator),
            .ForeignKey => |fk| fk.deinit(allocator),
            .Check => |check| check.deinit(allocator),
            else => {},
        }
    }
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
    Parameter: u32, // Parameter placeholder index

    pub fn deinit(self: *Expression, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Column => |col| allocator.free(col),
            .Literal => |value| value.deinit(allocator),
            .Parameter => {},
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
    Parameter: u32, // Parameter placeholder index

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

/// Foreign key constraint
pub const ForeignKeyConstraint = struct {
    column: ?[]const u8, // null for column-level, set for table-level
    reference_table: []const u8,
    reference_column: []const u8,
    on_delete: ?ForeignKeyAction,
    on_update: ?ForeignKeyAction,
    
    pub fn deinit(self: ForeignKeyConstraint, allocator: std.mem.Allocator) void {
        if (self.column) |col| {
            allocator.free(col);
        }
        allocator.free(self.reference_table);
        allocator.free(self.reference_column);
    }
};

/// Foreign key action
pub const ForeignKeyAction = enum {
    Cascade,
    SetNull,
    Restrict,
    NoAction,
};

/// Check constraint
pub const CheckConstraint = struct {
    condition: Condition,
    
    pub fn deinit(self: CheckConstraint, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Condition cleanup handled by parent
    }
};

/// Table-level constraints
pub const TableConstraint = union(enum) {
    ForeignKey: ForeignKeyConstraint,
    Unique: UniqueConstraint,
    Check: CheckConstraint,
    PrimaryKey: PrimaryKeyConstraint,
    
    pub fn deinit(self: TableConstraint, allocator: std.mem.Allocator) void {
        switch (self) {
            .ForeignKey => |fk| fk.deinit(allocator),
            .Unique => |unique| unique.deinit(allocator),
            .Check => |check| check.deinit(allocator),
            .PrimaryKey => |pk| pk.deinit(allocator),
        }
    }
};

/// Multi-column unique constraint
pub const UniqueConstraint = struct {
    columns: [][]const u8,
    
    pub fn deinit(self: UniqueConstraint, allocator: std.mem.Allocator) void {
        for (self.columns) |column| {
            allocator.free(column);
        }
        allocator.free(self.columns);
    }
};

/// Multi-column primary key constraint
pub const PrimaryKeyConstraint = struct {
    columns: [][]const u8,
    
    pub fn deinit(self: PrimaryKeyConstraint, allocator: std.mem.Allocator) void {
        for (self.columns) |column| {
            allocator.free(column);
        }
        allocator.free(self.columns);
    }
};

/// Transaction statement
pub const TransactionStatement = struct {
    savepoint_name: ?[]const u8,
    
    pub fn deinit(self: *TransactionStatement, allocator: std.mem.Allocator) void {
        if (self.savepoint_name) |name| {
            allocator.free(name);
        }
    }
};

/// Create index statement
pub const CreateIndexStatement = struct {
    index_name: []const u8,
    table_name: []const u8,
    columns: [][]const u8,
    unique: bool,
    if_not_exists: bool,
    
    pub fn deinit(self: *CreateIndexStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.index_name);
        allocator.free(self.table_name);
        for (self.columns) |col| {
            allocator.free(col);
        }
        allocator.free(self.columns);
    }
};

/// Drop index statement
pub const DropIndexStatement = struct {
    index_name: []const u8,
    if_exists: bool,
    
    pub fn deinit(self: *DropIndexStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.index_name);
    }
};

/// Common Table Expression (CTE) statement
pub const WithStatement = struct {
    cte_definitions: []CTEDefinition,
    recursive: bool,
    main_query: SelectStatement,
    
    pub fn deinit(self: *WithStatement, allocator: std.mem.Allocator) void {
        for (self.cte_definitions) |*cte| {
            cte.deinit(allocator);
        }
        allocator.free(self.cte_definitions);
        self.main_query.deinit(allocator);
    }
};

/// CTE definition
pub const CTEDefinition = struct {
    name: []const u8,
    column_names: ?[][]const u8, // Optional column list
    query: SelectStatement,
    
    pub fn deinit(self: *CTEDefinition, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.column_names) |cols| {
            for (cols) |col| {
                allocator.free(col);
            }
            allocator.free(cols);
        }
        self.query.deinit(allocator);
    }
};

/// Window function for PostgreSQL compatibility
pub const WindowFunction = struct {
    function_type: WindowFunctionType,
    arguments: []FunctionArgument,
    window_spec: WindowSpecification,
    
    pub fn deinit(self: *WindowFunction, allocator: std.mem.Allocator) void {
        for (self.arguments) |arg| {
            arg.deinit(allocator);
        }
        allocator.free(self.arguments);
        self.window_spec.deinit(allocator);
    }
};

/// Window function types
pub const WindowFunctionType = enum {
    RowNumber,
    Rank,
    DenseRank,
    PercentRank,
    CumeDist,
    Ntile,
    Lag,
    Lead,
    FirstValue,
    LastValue,
    NthValue,
};

/// Window specification
pub const WindowSpecification = struct {
    window_name: ?[]const u8, // Reference to named window
    partition_by: ?[][]const u8, // PARTITION BY columns
    order_by: ?[]OrderByClause, // ORDER BY within window
    frame_clause: ?FrameClause, // Window frame specification
    
    pub fn deinit(self: *WindowSpecification, allocator: std.mem.Allocator) void {
        if (self.window_name) |name| {
            allocator.free(name);
        }
        if (self.partition_by) |cols| {
            for (cols) |col| {
                allocator.free(col);
            }
            allocator.free(cols);
        }
        if (self.order_by) |order_by| {
            for (order_by) |clause| {
                allocator.free(clause.column);
            }
            allocator.free(order_by);
        }
        if (self.frame_clause) |*frame| {
            frame.deinit(allocator);
        }
    }
};

/// Window frame clause
pub const FrameClause = struct {
    frame_type: FrameType,
    start_bound: FrameBound,
    end_bound: ?FrameBound,
    
    pub fn deinit(self: *FrameClause, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // No dynamic memory to free in current implementation
    }
};

/// Window frame types
pub const FrameType = enum {
    Rows,
    Range,
    Groups,
};

/// Window frame bound
pub const FrameBound = enum {
    UnboundedPreceding,
    UnboundedFollowing,
    CurrentRow,
    Preceding,
    Following,
};

/// Window definition (for WINDOW clause)
pub const WindowDefinition = struct {
    name: []const u8,
    specification: WindowSpecification,
    
    pub fn deinit(self: *WindowDefinition, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.specification.deinit(allocator);
    }
};

/// UUID utility functions
pub const UUIDUtils = struct {
    /// Generate a random UUID v4
    pub fn generateV4(random: std.Random) [16]u8 {
        var uuid: [16]u8 = undefined;
        random.bytes(&uuid);
        
        // Set version to 4 (random UUID)
        uuid[6] = (uuid[6] & 0x0F) | 0x40;
        
        // Set variant bits
        uuid[8] = (uuid[8] & 0x3F) | 0x80;
        
        return uuid;
    }
    
    /// Parse UUID from string representation
    pub fn parseFromString(uuid_str: []const u8) ![16]u8 {
        if (uuid_str.len != 36) return error.InvalidUUIDFormat;
        
        var uuid: [16]u8 = undefined;
        var uuid_idx: usize = 0;
        var str_idx: usize = 0;
        
        while (str_idx < uuid_str.len and uuid_idx < 16) {
            if (uuid_str[str_idx] == '-') {
                str_idx += 1;
                continue;
            }
            
            if (str_idx + 1 >= uuid_str.len) return error.InvalidUUIDFormat;
            
            uuid[uuid_idx] = try std.fmt.parseInt(u8, uuid_str[str_idx..str_idx + 2], 16);
            uuid_idx += 1;
            str_idx += 2;
        }
        
        if (uuid_idx != 16) return error.InvalidUUIDFormat;
        return uuid;
    }
    
    /// Convert UUID to string representation
    pub fn toString(uuid: [16]u8, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, 
            "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
            .{ uuid[0], uuid[1], uuid[2], uuid[3], uuid[4], uuid[5], uuid[6], uuid[7],
               uuid[8], uuid[9], uuid[10], uuid[11], uuid[12], uuid[13], uuid[14], uuid[15] });
    }
};

test "ast creation" {
    try std.testing.expect(true); // Placeholder
}

test "uuid generation and parsing" {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();
    
    // Test UUID generation
    const uuid = UUIDUtils.generateV4(random);
    try std.testing.expect(uuid.len == 16);
    
    // Test UUID string conversion
    const uuid_str = try UUIDUtils.toString(uuid, std.testing.allocator);
    defer std.testing.allocator.free(uuid_str);
    try std.testing.expect(uuid_str.len == 36);
    
    // Test UUID parsing
    const parsed_uuid = try UUIDUtils.parseFromString(uuid_str);
    try std.testing.expectEqualSlices(u8, &uuid, &parsed_uuid);
}
