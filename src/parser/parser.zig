const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const ast = @import("ast.zig");

/// Enhanced parser error with context
pub const ParseError = struct {
    position: usize,
    expected: []const u8,
    found: []const u8,
    message: []const u8,
    
    pub fn deinit(self: ParseError, allocator: std.mem.Allocator) void {
        allocator.free(self.expected);
        allocator.free(self.found);
        allocator.free(self.message);
    }
};

/// SQL parser that converts tokens into AST
pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokenizer: tokenizer.Tokenizer,
    current_token: tokenizer.Token,
    parameter_index: u32, // Track current parameter index for ? placeholders

    const Self = @This();

    /// Initialize parser with SQL input
    pub fn init(allocator: std.mem.Allocator, sql: []const u8) !Self {
        var tkn = tokenizer.Tokenizer.init(sql);
        const first_token = try tkn.nextToken(allocator);

        return Self{
            .allocator = allocator,
            .tokenizer = tkn,
            .current_token = first_token,
            .parameter_index = 0,
        };
    }

    /// Parse SQL into AST
    pub fn parse(self: *Self) !ast.Statement {
        return switch (self.current_token) {
            .Select => try self.parseSelect(),
            .Insert => try self.parseInsert(),
            .Create => try self.parseCreate(),
            .Update => try self.parseUpdate(),
            .Delete => try self.parseDelete(),
            else => error.UnexpectedToken,
        };
    }

    /// Parse SELECT statement
    fn parseSelect(self: *Self) !ast.Statement {
        try self.expect(.Select);

        // Parse columns
        var columns = std.ArrayList(ast.Column).init(self.allocator);
        defer columns.deinit();

        if (std.meta.activeTag(self.current_token) == .Asterisk) {
            try self.advance();
            try columns.append(ast.Column{ 
                .name = try self.allocator.dupe(u8, "*"), 
                .expression = ast.ColumnExpression{ .Simple = try self.allocator.dupe(u8, "*") },
                .alias = null 
            });
        } else {
            while (true) {
                const column = try self.parseColumn();
                try columns.append(column);

                if (std.meta.activeTag(self.current_token) == .Comma) {
                    try self.advance();
                } else {
                    break;
                }
            }
        }

        // Parse FROM clause
        try self.expect(.From);
        const table_name = try self.expectIdentifier();

        // Parse optional WHERE clause
        var where_clause: ?ast.WhereClause = null;
        if (std.meta.activeTag(self.current_token) == .Where) {
            try self.advance();
            where_clause = try self.parseWhere();
        }

        // Parse optional LIMIT clause
        var limit: ?u32 = null;
        if (std.meta.activeTag(self.current_token) == .Limit) {
            try self.advance();
            if (self.current_token == .Integer) {
                limit = @intCast(self.current_token.Integer);
                try self.advance();
            } else {
                return error.ExpectedNumber;
            }
        }

        // Parse optional OFFSET clause
        var offset: ?u32 = null;
        if (std.meta.activeTag(self.current_token) == .Offset) {
            try self.advance();
            if (self.current_token == .Integer) {
                offset = @intCast(self.current_token.Integer);
                try self.advance();
            } else {
                return error.ExpectedNumber;
            }
        }

        return ast.Statement{
            .Select = ast.SelectStatement{
                .columns = try columns.toOwnedSlice(),
                .table = table_name,
                .joins = &.{}, // Empty joins array for now
                .where_clause = where_clause,
                .group_by = null, // Not implemented yet
                .having = null, // Not implemented yet
                .order_by = null, // Not implemented yet
                .limit = limit,
                .offset = offset,
            },
        };
    }

    /// Parse INSERT statement
    fn parseInsert(self: *Self) !ast.Statement {
        try self.expect(.Insert);
        try self.expect(.Into);

        const table_name = try self.expectIdentifier();

        // Parse optional column list
        var columns: ?[][]const u8 = null;
        if (std.meta.activeTag(self.current_token) == .LeftParen) {
            try self.advance();
            var column_list = std.ArrayList([]const u8).init(self.allocator);
            defer column_list.deinit();

            while (true) {
                const col = try self.expectIdentifier();
                try column_list.append(col);

                if (std.meta.activeTag(self.current_token) == .Comma) {
                    try self.advance();
                } else {
                    break;
                }
            }

            try self.expect(.RightParen);
            columns = try column_list.toOwnedSlice();
        }

        // Parse VALUES clause
        try self.expect(.Values);

        var values = std.ArrayList([]ast.Value).init(self.allocator);
        defer values.deinit();

        // Parse value rows
        while (true) {
            try self.expect(.LeftParen);

            var row = std.ArrayList(ast.Value).init(self.allocator);
            defer row.deinit();

            while (true) {
                const value = try self.parseValue();
                try row.append(value);

                if (std.meta.activeTag(self.current_token) == .Comma) {
                    try self.advance();
                } else {
                    break;
                }
            }

            try self.expect(.RightParen);
            try values.append(try row.toOwnedSlice());

            if (std.meta.activeTag(self.current_token) == .Comma) {
                try self.advance();
            } else {
                break;
            }
        }

        return ast.Statement{
            .Insert = ast.InsertStatement{
                .table = table_name,
                .columns = columns,
                .values = try values.toOwnedSlice(),
            },
        };
    }

    /// Parse CREATE TABLE statement
    fn parseCreate(self: *Self) !ast.Statement {
        try self.expect(.Create);
        try self.expect(.Table);

        // Parse optional IF NOT EXISTS
        var if_not_exists = false;
        if (std.meta.activeTag(self.current_token) == .If) {
            try self.advance();
            try self.expect(.Not);
            try self.expect(.Exists);
            if_not_exists = true;
        }

        const table_name = try self.expectIdentifier();

        try self.expect(.LeftParen);

        var columns = std.ArrayList(ast.ColumnDefinition).init(self.allocator);
        defer columns.deinit();

        while (true) {
            const column = try self.parseColumnDefinition();
            try columns.append(column);

            if (std.meta.activeTag(self.current_token) == .Comma) {
                try self.advance();
            } else {
                break;
            }
        }

        try self.expect(.RightParen);

        return ast.Statement{
            .CreateTable = ast.CreateTableStatement{
                .table_name = table_name,
                .columns = try columns.toOwnedSlice(),
                .if_not_exists = if_not_exists,
            },
        };
    }

    /// Parse UPDATE statement
    fn parseUpdate(self: *Self) !ast.Statement {
        try self.expect(.Update);
        const table_name = try self.expectIdentifier();
        try self.expect(.Set);

        var assignments = std.ArrayList(ast.Assignment).init(self.allocator);
        defer assignments.deinit();

        while (true) {
            const column = try self.expectIdentifier();
            try self.expect(.Equal);
            const value = try self.parseValue();

            try assignments.append(ast.Assignment{
                .column = column,
                .value = value,
            });

            if (std.meta.activeTag(self.current_token) == .Comma) {
                try self.advance();
            } else {
                break;
            }
        }

        var where_clause: ?ast.WhereClause = null;
        if (std.meta.activeTag(self.current_token) == .Where) {
            try self.advance();
            where_clause = try self.parseWhere();
        }

        return ast.Statement{
            .Update = ast.UpdateStatement{
                .table = table_name,
                .assignments = try assignments.toOwnedSlice(),
                .where_clause = where_clause,
            },
        };
    }

    /// Parse DELETE statement
    fn parseDelete(self: *Self) !ast.Statement {
        try self.expect(.Delete);
        try self.expect(.From);
        const table_name = try self.expectIdentifier();

        var where_clause: ?ast.WhereClause = null;
        if (std.meta.activeTag(self.current_token) == .Where) {
            try self.advance();
            where_clause = try self.parseWhere();
        }

        return ast.Statement{
            .Delete = ast.DeleteStatement{
                .table = table_name,
                .where_clause = where_clause,
            },
        };
    }

    /// Parse a column in SELECT
    fn parseColumn(self: *Self) !ast.Column {
        const name = try self.expectIdentifier();
        var alias: ?[]const u8 = null;

        // Check for AS alias or implicit alias
        if (std.meta.activeTag(self.current_token) == .Identifier) {
            alias = try self.expectIdentifier();
        }

        return ast.Column{ 
            .name = name, 
            .expression = ast.ColumnExpression{ .Simple = name },
            .alias = alias 
        };
    }

    /// Parse a column definition in CREATE TABLE
    fn parseColumnDefinition(self: *Self) !ast.ColumnDefinition {
        const name = try self.expectIdentifier();
        const data_type = try self.parseDataType();

        var constraints = std.ArrayList(ast.ColumnConstraint).init(self.allocator);
        defer constraints.deinit();

        // Parse constraints
        while (true) {
            const constraint = self.parseConstraint() catch break;
            try constraints.append(constraint);
        }

        return ast.ColumnDefinition{
            .name = name,
            .data_type = data_type,
            .constraints = try constraints.toOwnedSlice(),
        };
    }

    /// Parse data type
    fn parseDataType(self: *Self) !ast.DataType {
        const type_name = try self.expectIdentifier();
        defer self.allocator.free(type_name);

        if (std.mem.eql(u8, type_name, "INTEGER") or std.mem.eql(u8, type_name, "integer")) {
            return .Integer;
        } else if (std.mem.eql(u8, type_name, "TEXT") or std.mem.eql(u8, type_name, "text")) {
            return .Text;
        } else if (std.mem.eql(u8, type_name, "REAL") or std.mem.eql(u8, type_name, "real")) {
            return .Real;
        } else if (std.mem.eql(u8, type_name, "BLOB") or std.mem.eql(u8, type_name, "blob")) {
            return .Blob;
        } else {
            return error.UnknownDataType;
        }
    }

    /// Parse column constraint
    fn parseConstraint(self: *Self) !ast.ColumnConstraint {
        return switch (self.current_token) {
            .Primary => {
                try self.advance();
                try self.expect(.Key);
                return .PrimaryKey;
            },
            .Not => {
                try self.advance();
                try self.expect(.Null);
                return .NotNull;
            },
            .Unique => {
                try self.advance();
                return .Unique;
            },
            .Default => {
                try self.advance();
                const default_value = try self.parseDefaultValue();
                return ast.ColumnConstraint{ .Default = default_value };
            },
            else => error.UnexpectedToken,
        };
    }

    /// Parse default value for column constraints
    fn parseDefaultValue(self: *Self) !ast.DefaultValue {
        // Check for parenthesized expressions like (strftime('%s','now'))
        if (std.meta.activeTag(self.current_token) == .LeftParen) {
            try self.advance(); // consume '('
            
            // Check if it's a function call inside parentheses
            if (self.current_token == .Identifier) {
                const function_call = try self.parseFunctionCall();
                try self.expect(.RightParen);
                return ast.DefaultValue{ .FunctionCall = function_call };
            }
            
            // Otherwise parse as expression and close paren
            const inner_value = try self.parseDefaultValue();
            try self.expect(.RightParen);
            return inner_value;
        }
        
        // Check if it's a direct function call (identifier followed by parentheses)
        if (self.current_token == .Identifier) {
            // Peek ahead to see if this is followed by a left paren
            if (try self.peekNextToken()) |next_token| {
                defer next_token.deinit(self.allocator);
                if (std.meta.activeTag(next_token) == .LeftParen) {
                    const function_call = try self.parseFunctionCall();
                    return ast.DefaultValue{ .FunctionCall = function_call };
                }
            }
            
            // Not a function call, treat as identifier (this shouldn't happen in DEFAULT context)
            return error.UnexpectedToken;
        }
        
        // Otherwise, it's a literal value
        const value = try self.parseValue();
        return ast.DefaultValue{ .Literal = value };
    }
    
    /// Parse function call
    fn parseFunctionCall(self: *Self) !ast.FunctionCall {
        const func_name = try self.expectIdentifier();
        
        // Check if there's actually a left paren (this is a safety check)
        if (std.meta.activeTag(self.current_token) != .LeftParen) {
            // Not actually a function call, this is an error in our logic
            return error.ExpectedLeftParen;
        }
        
        try self.expect(.LeftParen);
        
        var arguments = std.ArrayList(ast.FunctionArgument).init(self.allocator);
        defer arguments.deinit();
        
        // Parse arguments
        while (std.meta.activeTag(self.current_token) != .RightParen) {
            const arg = try self.parseFunctionArgument();
            try arguments.append(arg);
            
            if (std.meta.activeTag(self.current_token) == .Comma) {
                try self.advance();
            } else if (std.meta.activeTag(self.current_token) != .RightParen) {
                return error.ExpectedCommaOrRightParen;
            }
        }
        
        try self.expect(.RightParen);
        
        return ast.FunctionCall{
            .name = func_name,
            .arguments = try arguments.toOwnedSlice(),
        };
    }
    
    /// Parse function argument
    fn parseFunctionArgument(self: *Self) !ast.FunctionArgument {
        return switch (self.current_token) {
            .String => |s| {
                const owned_string = try self.allocator.dupe(u8, s);
                try self.advance();
                return ast.FunctionArgument{ .String = owned_string };
            },
            else => {
                const value = try self.parseValue();
                return ast.FunctionArgument{ .Literal = value };
            },
        };
    }

    /// Parse WHERE clause
    fn parseWhere(self: *Self) !ast.WhereClause {
        const condition = try self.parseCondition();
        return ast.WhereClause{ .condition = condition };
    }

    /// Parse condition in WHERE clause
    fn parseCondition(self: *Self) !ast.Condition {
        var left = ast.Condition{ .Comparison = try self.parseComparison() };

        while (std.meta.activeTag(self.current_token) == .And or std.meta.activeTag(self.current_token) == .Or) {
            const op: ast.LogicalOperator = if (std.meta.activeTag(self.current_token) == .And) .And else .Or;
            try self.advance();

            const right = try self.parseComparison();
            const left_ptr = try self.allocator.create(ast.Condition);
            left_ptr.* = left;

            const right_ptr = try self.allocator.create(ast.Condition);
            right_ptr.* = ast.Condition{ .Comparison = right };

            left = ast.Condition{
                .Logical = ast.LogicalCondition{
                    .left = left_ptr,
                    .operator = op,
                    .right = right_ptr,
                },
            };
        }

        return left;
    }

    /// Parse comparison condition
    fn parseComparison(self: *Self) !ast.ComparisonCondition {
        const left = try self.parseExpression();
        const op = try self.parseComparisonOperator();
        const right = try self.parseExpression();

        return ast.ComparisonCondition{
            .left = left,
            .operator = op,
            .right = right,
        };
    }

    /// Parse comparison operator
    fn parseComparisonOperator(self: *Self) !ast.ComparisonOperator {
        const op = switch (self.current_token) {
            .Equal => ast.ComparisonOperator.Equal,
            .NotEqual => ast.ComparisonOperator.NotEqual,
            .LessThan => ast.ComparisonOperator.LessThan,
            .LessThanOrEqual => ast.ComparisonOperator.LessThanOrEqual,
            .GreaterThan => ast.ComparisonOperator.GreaterThan,
            .GreaterThanOrEqual => ast.ComparisonOperator.GreaterThanOrEqual,
            .Like => ast.ComparisonOperator.Like,
            .In => ast.ComparisonOperator.In,
            else => return error.ExpectedOperator,
        };
        try self.advance();
        return op;
    }

    /// Parse expression (column or literal)
    fn parseExpression(self: *Self) !ast.Expression {
        return switch (self.current_token) {
            .Identifier => |id| {
                const owned_id = try self.allocator.dupe(u8, id);
                try self.advance();
                return ast.Expression{ .Column = owned_id };
            },
            .QuestionMark => {
                const param_index = self.parameter_index;
                self.parameter_index += 1;
                try self.advance();
                return ast.Expression{ .Parameter = param_index };
            },
            else => {
                const value = try self.parseValue();
                return ast.Expression{ .Literal = value };
            },
        };
    }

    /// Parse value literal
    fn parseValue(self: *Self) !ast.Value {
        const value = switch (self.current_token) {
            .Integer => |i| ast.Value{ .Integer = i },
            .Real => |r| ast.Value{ .Real = r },
            .String => |s| ast.Value{ .Text = try self.allocator.dupe(u8, s) },
            .Null => ast.Value.Null,
            .QuestionMark => blk: {
                const param_index = self.parameter_index;
                self.parameter_index += 1;
                break :blk ast.Value{ .Parameter = param_index };
            },
            else => return error.ExpectedValue,
        };
        try self.advance();
        return value;
    }

    /// Create detailed error message
    fn createError(self: *Self, expected: []const u8, context: []const u8) void {
        // For now, just log the error. In production, you'd want to store
        // the error details for better debugging.
        std.log.err("Parse error at position {d}: Expected {s}, found {any} {s}", .{
            self.tokenizer.position, expected, self.current_token, context
        });
    }

    /// Expect a specific token
    fn expect(self: *Self, expected: std.meta.Tag(tokenizer.Token)) !void {
        if (std.meta.activeTag(self.current_token) != expected) {
            self.createError(@tagName(expected), "");
            return error.UnexpectedToken;
        }
        try self.advance();
    }

    /// Expect an identifier and return its value
    fn expectIdentifier(self: *Self) ![]const u8 {
        if (self.current_token != .Identifier) {
            self.createError("identifier", "");
            return error.ExpectedIdentifier;
        }
        const value = try self.allocator.dupe(u8, self.current_token.Identifier);
        try self.advance();
        return value;
    }

    /// Advance to next token
    fn advance(self: *Self) !void {
        self.current_token.deinit(self.allocator);
        self.current_token = try self.tokenizer.nextToken(self.allocator);
    }

    /// Peek at the next token without consuming it
    fn peekNextToken(self: *Self) !?tokenizer.Token {
        // Create a copy of the current tokenizer state
        var peek_tokenizer = tokenizer.Tokenizer.init(self.tokenizer.input);
        peek_tokenizer.position = self.tokenizer.position;
        peek_tokenizer.current_char = self.tokenizer.current_char;
        
        // Get the next token without affecting our state
        return try peek_tokenizer.nextToken(self.allocator);
    }

    /// Clean up parser
    pub fn deinit(self: *Self) void {
        self.current_token.deinit(self.allocator);
    }
};

/// Parse SQL statement (convenience function)
pub fn parse(allocator: std.mem.Allocator, sql: []const u8) !ParseResult {
    var parser = try Parser.init(allocator, sql);
    const statement = try parser.parse();
    return ParseResult{
        .statement = statement,
        .parser = parser,
    };
}

/// Parse result that manages parser lifetime
pub const ParseResult = struct {
    statement: ast.Statement,
    parser: Parser,

    pub fn deinit(self: *ParseResult) void {
        self.statement.deinit(self.parser.allocator);
        self.parser.deinit();
    }
};

test "parse simple select" {
    const allocator = std.testing.allocator;
    var result = try parse(allocator, "SELECT * FROM users");
    defer result.deinit();

    try std.testing.expectEqual(std.meta.Tag(ast.Statement).Select, std.meta.activeTag(result.statement));
}

test "parse create table with default literal" {
    const allocator = std.testing.allocator;
    const sql = "CREATE TABLE users (id INTEGER DEFAULT 42)";
    
    var result = try parse(allocator, sql);
    defer result.deinit();

    try std.testing.expectEqual(std.meta.Tag(ast.Statement).CreateTable, std.meta.activeTag(result.statement));
    
    const create_stmt = result.statement.CreateTable;
    try std.testing.expectEqual(@as(usize, 1), create_stmt.columns.len);
    
    // Check the column has a default constraint
    const col = create_stmt.columns[0];
    try std.testing.expectEqual(@as(usize, 1), col.constraints.len);
    try std.testing.expectEqual(std.meta.Tag(ast.ColumnConstraint).Default, std.meta.activeTag(col.constraints[0]));
}

test "parse create table with default function call" {
    const allocator = std.testing.allocator;
    // Simplified test - the complex strftime parsing can be added later
    const sql = "CREATE TABLE users (id INTEGER PRIMARY KEY, created_at INTEGER DEFAULT 42)";
    
    var result = try parse(allocator, sql);
    defer result.deinit();

    try std.testing.expectEqual(std.meta.Tag(ast.Statement).CreateTable, std.meta.activeTag(result.statement));
    
    const create_stmt = result.statement.CreateTable;
    try std.testing.expectEqual(@as(usize, 2), create_stmt.columns.len);
    
    // Check the second column has a default constraint
    const second_col = create_stmt.columns[1];
    try std.testing.expectEqual(@as(usize, 1), second_col.constraints.len);
    try std.testing.expectEqual(std.meta.Tag(ast.ColumnConstraint).Default, std.meta.activeTag(second_col.constraints[0]));
}

test "parse insert with parameters" {
    const allocator = std.testing.allocator;
    const sql = "INSERT INTO users (id, name) VALUES (?, ?)";
    
    var result = try parse(allocator, sql);
    defer result.deinit();

    try std.testing.expectEqual(std.meta.Tag(ast.Statement).Insert, std.meta.activeTag(result.statement));
    
    const insert_stmt = result.statement.Insert;
    try std.testing.expectEqual(@as(usize, 1), insert_stmt.values.len);
    
    // Check that we have parameter placeholders
    const row = insert_stmt.values[0];
    try std.testing.expectEqual(@as(usize, 2), row.len);
    try std.testing.expectEqual(std.meta.Tag(ast.Value).Parameter, std.meta.activeTag(row[0]));
    try std.testing.expectEqual(std.meta.Tag(ast.Value).Parameter, std.meta.activeTag(row[1]));
    try std.testing.expectEqual(@as(u32, 0), row[0].Parameter);
    try std.testing.expectEqual(@as(u32, 1), row[1].Parameter);
}

test "parse strftime function in default" {
    const allocator = std.testing.allocator;
    // Test the exact case that was failing
    const sql = "CREATE TABLE test (created INTEGER DEFAULT (strftime('%s','now')))";
    
    var result = try parse(allocator, sql);
    defer result.deinit();

    try std.testing.expectEqual(std.meta.Tag(ast.Statement).CreateTable, std.meta.activeTag(result.statement));
}
