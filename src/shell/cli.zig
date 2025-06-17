const std = @import("std");
const zqlite = @import("../zqlite.zig");

/// Interactive CLI shell for zqlite
pub const Shell = struct {
    allocator: std.mem.Allocator,
    connection: ?*zqlite.db.Connection,
    prepared_stmt: ?*zqlite.db.PreparedStatement,
    running: bool,

    const Self = @This();

    /// Initialize shell
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .connection = null,
            .prepared_stmt = null,
            .running = true,
        };
    }

    /// Start the interactive shell
    pub fn run(self: *Self) !void {
        const stdin = std.io.getStdIn().reader();

        std.debug.print("🟦 zqlite v{s} - Interactive Shell\n", .{zqlite.version});
        std.debug.print("Type '.help' for commands or '.quit' to exit\n\n", .{});

        while (self.running) {
            std.debug.print("zql> ", .{});

            // Read input
            var buffer: [1024]u8 = undefined;
            if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |input| {
                const trimmed = std.mem.trim(u8, input, " \t\n\r");
                if (trimmed.len == 0) continue;

                try self.processCommand(trimmed);
            } else {
                break; // EOF
            }
        }

        if (self.connection) |conn| {
            conn.close();
        }
        if (self.prepared_stmt) |stmt| {
            stmt.deinit();
        }
        std.debug.print("Goodbye!\n", .{});
    }

    /// Process a command
    fn processCommand(self: *Self, input: []const u8) !void {
        if (input[0] == '.') {
            try self.processMetaCommand(input);
        } else {
            try self.processSqlCommand(input);
        }
    }

    /// Process meta commands (.help, .quit, etc.)
    fn processMetaCommand(self: *Self, input: []const u8) !void {
        if (std.mem.eql(u8, input, ".quit") or std.mem.eql(u8, input, ".exit")) {
            self.running = false;
        } else if (std.mem.eql(u8, input, ".help")) {
            self.printHelp();
        } else if (std.mem.startsWith(u8, input, ".open ")) {
            const path = input[6..]; // Skip ".open "
            try self.openDatabase(path);
        } else if (std.mem.eql(u8, input, ".memory")) {
            try self.openMemoryDatabase();
        } else if (std.mem.eql(u8, input, ".close")) {
            try self.closeDatabase();
        } else if (std.mem.eql(u8, input, ".tables")) {
            try self.showTables();
        } else if (std.mem.eql(u8, input, ".schema")) {
            try self.showSchema();
        } else if (std.mem.eql(u8, input, ".stats")) {
            try self.showStats();
        } else if (std.mem.startsWith(u8, input, ".prepare ")) {
            const sql = input[9..]; // Skip ".prepare "
            try self.prepareStatement(sql);
        } else if (std.mem.startsWith(u8, input, ".bind ")) {
            const args = input[6..]; // Skip ".bind "
            try self.bindParameter(args);
        } else if (std.mem.eql(u8, input, ".execute")) {
            try self.executePrepared();
        } else {
            std.debug.print("Unknown command: {s}\n", .{input});
            std.debug.print("Type '.help' for available commands\n", .{});
        }
    }

    /// Process SQL commands
    fn processSqlCommand(self: *Self, input: []const u8) !void {
        if (self.connection == null) {
            std.debug.print("Error: No database open. Use '.open <path>' or '.memory'\n", .{});
            return;
        }

        const conn = self.connection.?;

        // Execute the SQL
        conn.execute(input) catch |err| {
            std.debug.print("SQL Error: {}\n", .{err});
            return;
        };

        std.debug.print("Command executed successfully\n", .{});
    }

    /// Print help information
    fn printHelp(self: *Self) void {
        _ = self;
        std.debug.print("zqlite Commands:\n", .{});
        std.debug.print("  .help                Show this help\n", .{});
        std.debug.print("  .quit, .exit         Exit the shell\n", .{});
        std.debug.print("  .open <path>         Open database file\n", .{});
        std.debug.print("  .memory              Open in-memory database\n", .{});
        std.debug.print("  .close               Close current database\n", .{});
        std.debug.print("  .tables              List tables\n", .{});
        std.debug.print("  .schema              Show schema\n", .{});
        std.debug.print("  .stats               Show database statistics\n", .{});
        std.debug.print("  .prepare <sql>       Prepare a SQL statement\n", .{});
        std.debug.print("  .bind <index> <val>  Bind parameter to prepared statement\n", .{});
        std.debug.print("  .execute             Execute prepared statement\n", .{});
        std.debug.print("\nSQL Commands:\n", .{});
        std.debug.print("  CREATE TABLE ...     Create a new table\n", .{});
        std.debug.print("  INSERT INTO ...      Insert data\n", .{});
        std.debug.print("  SELECT ...           Query data\n", .{});
        std.debug.print("  UPDATE ...           Update data\n", .{});
        std.debug.print("  DELETE ...           Delete data\n", .{});
        std.debug.print("\nExample:\n", .{});
        std.debug.print("  CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);\n", .{});
        std.debug.print("  INSERT INTO users VALUES (1, 'Alice');\n", .{});
        std.debug.print("  SELECT * FROM users;\n", .{});
        std.debug.print("\nPrepared Statements:\n", .{});
        std.debug.print("  .prepare INSERT INTO users VALUES (?, ?);\n", .{});
        std.debug.print("  .bind 0 42\n", .{});
        std.debug.print("  .bind 1 \"Bob\"\n", .{});
        std.debug.print("  .execute\n", .{});
    }

    /// Open a database file
    fn openDatabase(self: *Self, path: []const u8) !void {
        if (self.connection) |conn| {
            conn.close();
        }

        self.connection = zqlite.db.Connection.open(path) catch |err| {
            std.debug.print("Error opening database '{s}': {}\n", .{ path, err });
            return;
        };

        std.debug.print("Opened database: {s}\n", .{path});
    }

    /// Open an in-memory database
    fn openMemoryDatabase(self: *Self) !void {
        if (self.connection) |conn| {
            conn.close();
        }

        self.connection = zqlite.db.Connection.openMemory() catch |err| {
            std.debug.print("Error opening memory database: {}\n", .{err});
            return;
        };

        std.debug.print("Opened in-memory database\n", .{});
    }

    /// Close current database
    fn closeDatabase(self: *Self) !void {
        if (self.connection) |conn| {
            conn.close();
            self.connection = null;
            std.debug.print("Database closed\n", .{});
        } else {
            std.debug.print("No database open\n", .{});
        }
    }

    /// Show tables
    fn showTables(self: *Self) !void {
        if (self.connection == null) {
            std.debug.print("No database open\n", .{});
            return;
        }

        std.debug.print("Tables:\n", .{});
        std.debug.print("  (Table listing not yet implemented)\n", .{});
    }

    /// Show schema
    fn showSchema(self: *Self) !void {
        if (self.connection == null) {
            std.debug.print("No database open\n", .{});
            return;
        }

        std.debug.print("Schema:\n", .{});
        std.debug.print("  (Schema display not yet implemented)\n", .{});
    }

    /// Show database statistics
    fn showStats(self: *Self) !void {
        if (self.connection == null) {
            std.debug.print("No database open\n", .{});
            return;
        }

        const conn = self.connection.?;
        const stats = conn.storage_engine.getStats();
        const info = conn.info();

        std.debug.print("Database Statistics:\n", .{});
        std.debug.print("  Type: {s}\n", .{if (info.is_memory) "In-memory" else "File"});
        if (info.path) |path| {
            std.debug.print("  Path: {s}\n", .{path});
        }
        std.debug.print("  Tables: {d}\n", .{stats.table_count});
        std.debug.print("  Indexes: {d}\n", .{stats.index_count});
        std.debug.print("  Pages: {d}\n", .{stats.page_count});
        std.debug.print("  Cached Pages: {d}\n", .{stats.cached_pages});
        std.debug.print("  Cache Hit Ratio: {d:.2}%\n", .{stats.cache_hit_ratio * 100.0});
        std.debug.print("  WAL: {s}\n", .{if (info.has_wal) "Enabled" else "Disabled"});
    }

    /// Prepare a statement
    fn prepareStatement(self: *Self, sql: []const u8) !void {
        if (self.connection == null) {
            std.debug.print("No database open\n", .{});
            return;
        }

        // Clean up any existing prepared statement
        if (self.prepared_stmt) |stmt| {
            stmt.deinit();
        }

        const conn = self.connection.?;
        self.prepared_stmt = conn.prepare(sql) catch |err| {
            std.debug.print("Error preparing statement: {}\n", .{err});
            return;
        };

        std.debug.print("Statement prepared successfully\n", .{});
    }

    /// Bind a parameter
    fn bindParameter(self: *Self, args: []const u8) !void {
        if (self.prepared_stmt == null) {
            std.debug.print("No prepared statement\n", .{});
            return;
        }

        // Simple parsing: "index value"
        var parts = std.mem.splitScalar(u8, args, ' ');
        const index_str = parts.next() orelse {
            std.debug.print("Usage: .bind <index> <value>\n", .{});
            return;
        };
        const value_str = parts.next() orelse {
            std.debug.print("Usage: .bind <index> <value>\n", .{});
            return;
        };

        const index = std.fmt.parseInt(u32, index_str, 10) catch {
            std.debug.print("Invalid index: {s}\n", .{index_str});
            return;
        };

        // Try to parse as integer, then text
        const value = if (std.fmt.parseInt(i64, value_str, 10)) |int_val|
            zqlite.storage.Value{ .Integer = int_val }
        else |_|
            zqlite.storage.Value{ .Text = try self.allocator.dupe(u8, value_str) };

        const stmt = self.prepared_stmt.?;
        stmt.bindParameter(index, value) catch |err| {
            std.debug.print("Error binding parameter: {}\n", .{err});
            return;
        };

        std.debug.print("Parameter {d} bound\n", .{index});
    }

    /// Execute prepared statement
    fn executePrepared(self: *Self) !void {
        if (self.prepared_stmt == null) {
            std.debug.print("No prepared statement\n", .{});
            return;
        }

        const conn = self.connection.?;
        const stmt = self.prepared_stmt.?;

        var result = stmt.execute(conn) catch |err| {
            std.debug.print("Error executing prepared statement: {}\n", .{err});
            return;
        };
        defer result.deinit(conn.allocator);

        std.debug.print("Prepared statement executed. Affected rows: {d}, Result rows: {d}\n", .{ result.affected_rows, result.rows.items.len });
    }
};

/// Run the interactive shell
pub fn runShell(allocator: std.mem.Allocator) !void {
    var shell = Shell.init(allocator);
    try shell.run();
}

/// Execute a single command (for CLI usage)
pub fn executeCommand(allocator: std.mem.Allocator, args: [][]const u8) !void {
    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "shell") or std.mem.eql(u8, command, "interactive")) {
        try runShell(allocator);
    } else if (std.mem.eql(u8, command, "version")) {
        std.debug.print("zqlite version {s}\n", .{zqlite.version});
    } else if (std.mem.eql(u8, command, "help")) {
        printUsage();
    } else if (args.len >= 3 and std.mem.eql(u8, command, "exec")) {
        // Execute SQL from command line
        const db_path = args[2];
        const sql = if (args.len >= 4) args[3] else {
            std.debug.print("Error: No SQL statement provided\n", .{});
            return;
        };

        try executeSQL(allocator, db_path, sql);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printUsage();
    }
}

/// Print usage information
fn printUsage() void {
    std.debug.print("zql - zqlite Command Line Interface\n\n", .{});
    std.debug.print("Usage:\n", .{});
    std.debug.print("  zql shell                    Start interactive shell\n", .{});
    std.debug.print("  zql exec <db> <sql>          Execute SQL statement\n", .{});
    std.debug.print("  zql version                  Show version\n", .{});
    std.debug.print("  zql help                     Show this help\n", .{});
    std.debug.print("\nExamples:\n", .{});
    std.debug.print("  zql shell\n", .{});
    std.debug.print("  zql exec mydb.db \"SELECT * FROM users;\"\n", .{});
}

/// Execute SQL from command line
fn executeSQL(allocator: std.mem.Allocator, db_path: []const u8, sql: []const u8) !void {
    _ = allocator; // Not needed for this simple execution
    const conn = zqlite.db.Connection.open(db_path) catch |err| {
        std.debug.print("Error opening database '{s}': {}\n", .{ db_path, err });
        return;
    };
    defer conn.close();

    conn.execute(sql) catch |err| {
        std.debug.print("SQL Error: {}\n", .{err});
        return;
    };

    std.debug.print("Command executed successfully\n", .{});
}
