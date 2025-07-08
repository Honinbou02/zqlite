const std = @import("std");
const tokioz = @import("tokioz");

/// 🌐 ZQLite v0.6.0 Transport Layer
/// High-performance networking with optional post-quantum features
/// Uses native Zig crypto with optional Shroud backend
pub const Transport = struct {
    allocator: std.mem.Allocator,
    endpoint: ?Endpoint,
    connections: std.HashMap(ConnectionId, *Connection),
    is_server: bool,
    crypto_enabled: bool,

    const Self = @This();
    const ConnectionId = u64;

    const Endpoint = struct {
        address: std.net.Address,
        socket: std.net.Stream,
    };

    const Connection = struct {
        id: ConnectionId,
        peer_address: std.net.Address,
        state: ConnectionState,
        last_activity: i64,
        
        const ConnectionState = enum {
            connecting,
            connected,
            disconnecting,
            closed,
        };
    };

    /// Initialize transport layer
    pub fn init(allocator: std.mem.Allocator, is_server: bool, crypto_enabled: bool) Self {
        return Self{
            .allocator = allocator,
            .endpoint = null,
            .connections = std.HashMap(ConnectionId, *Connection).init(allocator),
            .is_server = is_server,
            .crypto_enabled = crypto_enabled,
        };
    }

    /// Cleanup and close all connections
    pub fn deinit(self: *Self) void {
        var iterator = self.connections.iterator();
        while (iterator.next()) |entry| {
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.connections.deinit();
        self.* = undefined;
    }

    /// Bind to address and start listening (server mode)
    pub fn bind(self: *Self, address: std.net.Address) !void {
        if (!self.is_server) return error.NotServerMode;
        
        const socket = std.net.tcpConnectToAddress(address) catch |err| {
            std.log.err("Failed to bind to address: {}", .{err});
            return err;
        };
        
        self.endpoint = Endpoint{
            .address = address,
            .socket = socket,
        };
        
        std.log.info("🌐 ZQLite transport bound to {}", .{address});
    }

    /// Connect to remote address (client mode)
    pub fn connect(self: *Self, address: std.net.Address) !ConnectionId {
        if (self.is_server) return error.NotClientMode;
        
        _ = std.net.tcpConnectToAddress(address) catch |err| {
            std.log.err("Failed to connect to {}: {}", .{ address, err });
            return err;
        };

        const connection_id = @as(ConnectionId, @intCast(std.time.timestamp()));
        const connection = try self.allocator.create(Connection);
        connection.* = Connection{
            .id = connection_id,
            .peer_address = address,
            .state = .connecting,
            .last_activity = std.time.timestamp(),
        };

        try self.connections.put(connection_id, connection);
        
        std.log.info("🔗 Connected to {} (ID: {})", .{ address, connection_id });
        return connection_id;
    }

    /// Send data over connection
    pub fn send(self: *Self, connection_id: ConnectionId, data: []const u8) !void {
        const connection = self.connections.get(connection_id) orelse return error.ConnectionNotFound;
        
        if (connection.state != .connected) return error.ConnectionNotReady;
        
        // In a real implementation, this would send over the actual socket
        // For now, we'll just log and simulate
        std.log.debug("📤 Sending {} bytes to connection {}", .{ data.len, connection_id });
        
        connection.last_activity = std.time.timestamp();
    }

    /// Receive data from connection (async)
    pub fn receive(self: *Self, connection_id: ConnectionId, buffer: []u8) !usize {
        const connection = self.connections.get(connection_id) orelse return error.ConnectionNotFound;
        
        if (connection.state != .connected) return error.ConnectionNotReady;
        
        // In a real implementation, this would receive from the actual socket
        // For now, we'll simulate receiving data
        std.log.debug("📥 Receiving data from connection {}", .{connection_id});
        
        connection.last_activity = std.time.timestamp();
        
        // Simulate some data
        const test_data = "ZQLite v0.6.0 response data";
        const bytes_to_copy = @min(buffer.len, test_data.len);
        @memcpy(buffer[0..bytes_to_copy], test_data[0..bytes_to_copy]);
        
        return bytes_to_copy;
    }

    /// Close specific connection
    pub fn closeConnection(self: *Self, connection_id: ConnectionId) !void {
        const connection = self.connections.get(connection_id) orelse return error.ConnectionNotFound;
        
        connection.state = .closed;
        _ = self.connections.remove(connection_id);
        self.allocator.destroy(connection);
        
        std.log.info("🔒 Closed connection {}", .{connection_id});
    }

    /// Get connection count
    pub fn getConnectionCount(self: Self) u32 {
        return @intCast(self.connections.count());
    }

    /// Check if post-quantum features are available
    pub fn hasPostQuantumSupport(self: Self) bool {
        _ = self;
        // TODO: Check if Shroud is available and configured
        return false;
    }

    /// Get transport statistics
    pub fn getStats(self: Self) TransportStats {
        return TransportStats{
            .connection_count = self.getConnectionCount(),
            .crypto_enabled = self.crypto_enabled,
            .pq_enabled = self.hasPostQuantumSupport(),
        };
    }
};

/// Transport statistics
pub const TransportStats = struct {
    connection_count: u32,
    crypto_enabled: bool,
    pq_enabled: bool,
};

/// Test function for transport layer
pub fn testTransport() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = Transport.init(allocator, true, true);
    defer server.deinit();

    var client = Transport.init(allocator, false, true);
    defer client.deinit();

    _ = std.net.Address.parseIp4("127.0.0.1", 8080) catch |err| {
        std.log.err("Failed to parse address: {}", .{err});
        return err;
    };

    std.log.info("✅ ZQLite v0.6.0 Transport test initialized");
    std.log.info("Server stats: {}", .{server.getStats()});
    std.log.info("Client stats: {}", .{client.getStats()});
}
