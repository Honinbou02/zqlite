const std = @import("std");

/// SQL tokenizer for lexical analysis
pub const Tokenizer = struct {
    input: []const u8,
    position: usize,
    current_char: ?u8,

    const Self = @This();

    /// Initialize tokenizer with SQL input
    pub fn init(input: []const u8) Self {
        return Self{
            .input = input,
            .position = 0,
            .current_char = if (input.len > 0) input[0] else null,
        };
    }

    /// Get the next token
    pub fn nextToken(self: *Self, allocator: std.mem.Allocator) !Token {
        while (self.current_char != null) {
            // Skip whitespace
            if (std.ascii.isWhitespace(self.current_char.?)) {
                self.skipWhitespace();
                continue;
            }

            // Numbers
            if (std.ascii.isDigit(self.current_char.?)) {
                return try self.readNumber(allocator);
            }

            // Identifiers and keywords
            if (std.ascii.isAlphabetic(self.current_char.?) or self.current_char.? == '_') {
                return try self.readIdentifier(allocator);
            }

            // String literals
            if (self.current_char.? == '\'' or self.current_char.? == '"') {
                return try self.readString(allocator);
            }

            // Operators and punctuation
            switch (self.current_char.?) {
                '=' => {
                    self.advance();
                    return Token{ .Equal = {} };
                },
                '!' => {
                    self.advance();
                    if (self.current_char == '=') {
                        self.advance();
                        return Token{ .NotEqual = {} };
                    }
                    return error.UnexpectedCharacter;
                },
                '<' => {
                    self.advance();
                    if (self.current_char == '=') {
                        self.advance();
                        return Token{ .LessThanOrEqual = {} };
                    }
                    return Token{ .LessThan = {} };
                },
                '>' => {
                    self.advance();
                    if (self.current_char == '=') {
                        self.advance();
                        return Token{ .GreaterThanOrEqual = {} };
                    }
                    return Token{ .GreaterThan = {} };
                },
                '(' => {
                    self.advance();
                    return Token{ .LeftParen = {} };
                },
                ')' => {
                    self.advance();
                    return Token{ .RightParen = {} };
                },
                ',' => {
                    self.advance();
                    return Token{ .Comma = {} };
                },
                ';' => {
                    self.advance();
                    return Token{ .Semicolon = {} };
                },
                '*' => {
                    self.advance();
                    return Token{ .Asterisk = {} };
                },
                else => {
                    return error.UnexpectedCharacter;
                },
            }
        }

        return Token{ .EOF = {} };
    }

    /// Advance to next character
    fn advance(self: *Self) void {
        self.position += 1;
        if (self.position >= self.input.len) {
            self.current_char = null;
        } else {
            self.current_char = self.input[self.position];
        }
    }

    /// Skip whitespace characters
    fn skipWhitespace(self: *Self) void {
        while (self.current_char != null and std.ascii.isWhitespace(self.current_char.?)) {
            self.advance();
        }
    }

    /// Read a number token
    fn readNumber(self: *Self, allocator: std.mem.Allocator) !Token {
        _ = allocator; // Not needed for number parsing
        const start = self.position;
        var has_dot = false;

        while (self.current_char != null and (std.ascii.isDigit(self.current_char.?) or self.current_char.? == '.')) {
            if (self.current_char.? == '.') {
                if (has_dot) break; // Second dot, stop parsing
                has_dot = true;
            }
            self.advance();
        }

        const number_str = self.input[start..self.position];

        if (has_dot) {
            const value = try std.fmt.parseFloat(f64, number_str);
            return Token{ .Real = value };
        } else {
            const value = try std.fmt.parseInt(i64, number_str, 10);
            return Token{ .Integer = value };
        }
    }

    /// Read an identifier or keyword
    fn readIdentifier(self: *Self, allocator: std.mem.Allocator) !Token {
        const start = self.position;

        while (self.current_char != null and
            (std.ascii.isAlphanumeric(self.current_char.?) or self.current_char.? == '_'))
        {
            self.advance();
        }

        const identifier = self.input[start..self.position];

        // Check if it's a keyword
        if (getKeyword(identifier)) |keyword| {
            return keyword;
        }

        // It's an identifier
        const owned_identifier = try allocator.dupe(u8, identifier);
        return Token{ .Identifier = owned_identifier };
    }

    /// Read a string literal
    fn readString(self: *Self, allocator: std.mem.Allocator) !Token {
        const quote_char = self.current_char.?;
        self.advance(); // Skip opening quote

        const start = self.position;

        while (self.current_char != null and self.current_char.? != quote_char) {
            self.advance();
        }

        if (self.current_char == null) {
            return error.UnterminatedString;
        }

        const string_content = self.input[start..self.position];
        self.advance(); // Skip closing quote

        const owned_string = try allocator.dupe(u8, string_content);
        return Token{ .String = owned_string };
    }
};

/// SQL tokens
pub const Token = union(enum) {
    // Literals
    Integer: i64,
    Real: f64,
    String: []const u8,
    Identifier: []const u8,

    // Keywords
    Select,
    From,
    Where,
    Insert,
    Into,
    Values,
    Update,
    Set,
    Delete,
    Create,
    Table,
    And,
    Or,
    Like,
    In,
    Null,
    Not,
    Primary,
    Key,
    Unique,
    Begin,
    Commit,
    Rollback,
    If,
    Exists,
    Limit,
    Offset,

    // Operators
    Equal,
    NotEqual,
    LessThan,
    LessThanOrEqual,
    GreaterThan,
    GreaterThanOrEqual,

    // Punctuation
    LeftParen,
    RightParen,
    Comma,
    Semicolon,
    Asterisk,

    // Special
    EOF,

    pub fn deinit(self: Token, allocator: std.mem.Allocator) void {
        switch (self) {
            .String => |str| allocator.free(str),
            .Identifier => |id| allocator.free(id),
            else => {},
        }
    }
};

/// Check if identifier is a keyword
fn getKeyword(identifier: []const u8) ?Token {
    const keyword_map = std.ComptimeStringMap(Token, .{
        .{ "SELECT", .Select },
        .{ "select", .Select },
        .{ "FROM", .From },
        .{ "from", .From },
        .{ "WHERE", .Where },
        .{ "where", .Where },
        .{ "INSERT", .Insert },
        .{ "insert", .Insert },
        .{ "INTO", .Into },
        .{ "into", .Into },
        .{ "VALUES", .Values },
        .{ "values", .Values },
        .{ "UPDATE", .Update },
        .{ "update", .Update },
        .{ "SET", .Set },
        .{ "set", .Set },
        .{ "DELETE", .Delete },
        .{ "delete", .Delete },
        .{ "CREATE", .Create },
        .{ "create", .Create },
        .{ "TABLE", .Table },
        .{ "table", .Table },
        .{ "AND", .And },
        .{ "and", .And },
        .{ "OR", .Or },
        .{ "or", .Or },
        .{ "LIKE", .Like },
        .{ "like", .Like },
        .{ "IN", .In },
        .{ "in", .In },
        .{ "NULL", .Null },
        .{ "null", .Null },
        .{ "NOT", .Not },
        .{ "not", .Not },
        .{ "PRIMARY", .Primary },
        .{ "primary", .Primary },
        .{ "KEY", .Key },
        .{ "key", .Key },
        .{ "UNIQUE", .Unique },
        .{ "unique", .Unique },
        .{ "BEGIN", .Begin },
        .{ "begin", .Begin },
        .{ "COMMIT", .Commit },
        .{ "commit", .Commit },
        .{ "ROLLBACK", .Rollback },
        .{ "rollback", .Rollback },
        .{ "IF", .If },
        .{ "if", .If },
        .{ "EXISTS", .Exists },
        .{ "exists", .Exists },
        .{ "LIMIT", .Limit },
        .{ "limit", .Limit },
        .{ "OFFSET", .Offset },
        .{ "offset", .Offset },
    });

    return keyword_map.get(identifier);
}

test "tokenizer basic" {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init("SELECT * FROM users");

    const token1 = try tokenizer.nextToken(allocator);
    defer token1.deinit(allocator);
    try std.testing.expectEqual(Token.Select, token1);

    const token2 = try tokenizer.nextToken(allocator);
    defer token2.deinit(allocator);
    try std.testing.expectEqual(Token.Asterisk, token2);

    const token3 = try tokenizer.nextToken(allocator);
    defer token3.deinit(allocator);
    try std.testing.expectEqual(Token.From, token3);
}

test "tokenizer numbers" {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init("42 3.14");

    const token1 = try tokenizer.nextToken(allocator);
    defer token1.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 42), token1.Integer);

    const token2 = try tokenizer.nextToken(allocator);
    defer token2.deinit(allocator);
    try std.testing.expectEqual(@as(f64, 3.14), token2.Real);
}
