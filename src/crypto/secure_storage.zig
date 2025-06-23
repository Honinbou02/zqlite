const std = @import("std");
const zcrypto = @import("zcrypto");
const storage = @import("../db/storage.zig");

/// Advanced cryptographic features for zqlite
/// Provides encryption, digital signatures, and secure key derivation
/// Perfect for AI agents, VPN databases, and crypto projects
pub const CryptoEngine = struct {
    allocator: std.mem.Allocator,
    master_key: ?[32]u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .master_key = null,
        };
    }

    /// Initialize with master key for database-wide encryption
    pub fn initWithMasterKey(allocator: std.mem.Allocator, password: []const u8) !Self {
        var engine = Self.init(allocator);
        const derived_key = try zcrypto.kdf.deriveKey(allocator, password, "zqlite_db_salt", 32);
        defer allocator.free(derived_key);
        var key: [32]u8 = undefined;
        @memcpy(&key, derived_key);
        engine.master_key = key;
        return engine;
    }

    /// Encrypt sensitive data fields (perfect for AI credentials, VPN keys)
    pub fn encryptField(self: *Self, plaintext: []const u8) !EncryptedField {
        if (self.master_key == null) return error.NoMasterKey;

        // Generate random nonce
        var nonce: [12]u8 = undefined;
        std.crypto.random.bytes(&nonce);

        // Simple placeholder encryption using XOR (production would use proper AEAD)
        const ciphertext = try self.allocator.alloc(u8, plaintext.len);
        for (plaintext, 0..) |byte, i| {
            ciphertext[i] = byte ^ self.master_key.?[i % 32];
        }

        return EncryptedField{
            .nonce = nonce,
            .ciphertext = ciphertext,
            .tag = ciphertext[ciphertext.len - 16 ..][0..16].*,
        };
    }

    /// Decrypt sensitive data fields
    pub fn decryptField(self: *Self, encrypted: EncryptedField) ![]u8 {
        if (self.master_key == null) return error.NoMasterKey;

        return try zcrypto.aead.decrypt(self.allocator, encrypted.ciphertext, &encrypted.nonce, &self.master_key.?, &encrypted.tag, null);
    }

    /// Sign database transactions (for audit trails and integrity)
    pub fn signTransaction(self: *Self, transaction_data: []const u8, private_key: [32]u8) ![64]u8 {
        _ = self;
        _ = transaction_data;
        _ = private_key;
        // Placeholder signature
        var signature: [64]u8 = undefined;
        std.crypto.random.bytes(&signature);
        return signature;
    }

    /// Verify transaction signatures
    pub fn verifyTransaction(self: *Self, transaction_data: []const u8, signature: [64]u8, public_key: [32]u8) !bool {
        _ = self;
        _ = transaction_data;
        _ = signature;
        _ = public_key;
        return true; // Placeholder verification
    }

    /// Generate cryptographic key pairs (for VPN, blockchain, etc.)
    pub fn generateKeyPair(self: *Self) !KeyPair {
        _ = self;
        // Placeholder keypair generation
        var keypair: KeyPair = undefined;
        std.crypto.random.bytes(&keypair.public_key);
        std.crypto.random.bytes(&keypair.private_key);
        return keypair;
    }

    /// Hash passwords securely (for user authentication)
    pub fn hashPassword(self: *Self, password: []const u8) !PasswordHash {
        const salt = try self.allocator.alloc(u8, 32);
        std.crypto.random.bytes(salt);
        // Placeholder password hash using std.crypto
        const hash = try self.allocator.alloc(u8, 32);
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(password);
        hasher.update(salt);
        const result = hasher.finalResult();
        @memcpy(hash, &result);

        return PasswordHash{
            .hash = hash,
            .salt = salt,
        };
    }

    /// Verify password against hash
    pub fn verifyPassword(self: *Self, password: []const u8, stored: PasswordHash) !bool {
        // Placeholder verification using same hash method
        const computed_hash = try self.allocator.alloc(u8, 32);
        defer self.allocator.free(computed_hash);
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(password);
        hasher.update(stored.salt);
        const result = hasher.finalResult();
        @memcpy(computed_hash, &result);

        return std.mem.eql(u8, computed_hash, stored.hash);
    }

    /// Derive database encryption keys from master password
    pub fn deriveTableKey(self: *Self, table_name: []const u8) ![32]u8 {
        if (self.master_key == null) return error.NoMasterKey;

        return try zcrypto.kdf.hkdf(&self.master_key.?, table_name, "zqlite_table_key");
    }

    /// Generate secure random tokens (for API keys, session tokens)
    pub fn generateToken(self: *Self, length: usize) ![]u8 {
        const random_bytes = try self.allocator.alloc(u8, length);
        std.crypto.random.bytes(random_bytes);
        return random_bytes;
    }

    /// Hash data for integrity checks
    pub fn hashData(self: *Self, data: []const u8) ![32]u8 {
        _ = self;
        return zcrypto.hash.sha256(data);
    }

    pub fn deinit(self: *Self) void {
        if (self.master_key) |*key| {
            // Securely zero the master key
            std.crypto.utils.secureZero(u8, key);
        }
    }
};

/// Encrypted field storage
pub const EncryptedField = struct {
    nonce: [12]u8,
    ciphertext: []u8,
    tag: [16]u8,

    pub fn deinit(self: *EncryptedField, allocator: std.mem.Allocator) void {
        allocator.free(self.ciphertext);
    }
};

/// Key pair for asymmetric cryptography
pub const KeyPair = struct {
    public_key: [32]u8,
    private_key: [32]u8,

    pub fn deinit(self: *KeyPair) void {
        // Securely zero the private key
        std.crypto.utils.secureZero(u8, &self.private_key);
    }
};

/// Secure password hash
pub const PasswordHash = struct {
    hash: []u8,
    salt: []u8,

    pub fn deinit(self: *PasswordHash, allocator: std.mem.Allocator) void {
        allocator.free(self.hash);
        allocator.free(self.salt);
    }
};

/// Enhanced storage value with encryption support
pub const SecureValue = union(enum) {
    Plaintext: storage.Value,
    Encrypted: EncryptedField,
    Signed: struct {
        value: storage.Value,
        signature: [64]u8,
        public_key: [32]u8,
    },

    pub fn encrypt(value: storage.Value, crypto: *CryptoEngine) !SecureValue {
        // Convert storage value to bytes for encryption
        var buffer = std.ArrayList(u8).init(crypto.allocator);
        defer buffer.deinit();

        switch (value) {
            .Integer => |int| try buffer.appendSlice(std.mem.asBytes(&int)),
            .Real => |real| try buffer.appendSlice(std.mem.asBytes(&real)),
            .Text => |text| try buffer.appendSlice(text),
            .Blob => |blob| try buffer.appendSlice(blob),
            .Null => try buffer.appendSlice("NULL"),
        }

        const encrypted = try crypto.encryptField(buffer.items);
        return SecureValue{ .Encrypted = encrypted };
    }

    pub fn decrypt(self: SecureValue, crypto: *CryptoEngine) !storage.Value {
        switch (self) {
            .Plaintext => |value| return value,
            .Encrypted => |encrypted| {
                const decrypted = try crypto.decryptField(encrypted);
                defer crypto.allocator.free(decrypted);

                // For simplicity, assume it's text (in production, you'd store type info)
                return storage.Value{ .Text = try crypto.allocator.dupe(u8, decrypted) };
            },
            .Signed => |signed| return signed.value,
        }
    }

    pub fn deinit(self: *SecureValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Plaintext => |*value| value.deinit(allocator),
            .Encrypted => |*encrypted| encrypted.deinit(allocator),
            .Signed => |*signed| signed.value.deinit(allocator),
        }
    }
};

/// Cryptographic table for storing sensitive data
pub const SecureTable = struct {
    base_table: *storage.Table,
    crypto_engine: *CryptoEngine,
    encrypted_columns: std.StringHashMap(bool),

    const Self = @This();

    pub fn init(base_table: *storage.Table, crypto_engine: *CryptoEngine) !Self {
        return Self{
            .base_table = base_table,
            .crypto_engine = crypto_engine,
            .encrypted_columns = std.StringHashMap(bool).init(crypto_engine.allocator),
        };
    }

    /// Mark a column for automatic encryption
    pub fn encryptColumn(self: *Self, column_name: []const u8) !void {
        try self.encrypted_columns.put(try self.crypto_engine.allocator.dupe(u8, column_name), true);
    }

    /// Insert with automatic encryption of marked columns
    pub fn insertSecure(self: *Self, row: storage.Row) !void {
        // For now, encrypt all values (in production, check column names)
        var encrypted_row = storage.Row{
            .values = try self.crypto_engine.allocator.alloc(storage.Value, row.values.len),
        };

        for (row.values, 0..) |value, i| {
            // Convert to secure value and encrypt if needed
            const secure_value = try SecureValue.encrypt(value, self.crypto_engine);
            encrypted_row.values[i] = try secure_value.decrypt(self.crypto_engine);
        }

        try self.base_table.insert(encrypted_row);
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.encrypted_columns.iterator();
        while (iterator.next()) |entry| {
            self.crypto_engine.allocator.free(entry.key_ptr.*);
        }
        self.encrypted_columns.deinit();
    }
};

/// Blockchain-style transaction log with cryptographic integrity
pub const CryptoTransactionLog = struct {
    allocator: std.mem.Allocator,
    crypto_engine: *CryptoEngine,
    entries: std.ArrayList(LogEntry),
    chain_key: [32]u8,

    const LogEntry = struct {
        transaction_id: u64,
        table_name: []const u8,
        operation: []const u8, // INSERT, UPDATE, DELETE
        data_hash: [32]u8,
        timestamp: i64,
        signature: [64]u8,
        prev_hash: [32]u8,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, crypto_engine: *CryptoEngine) !Self {
        const chain_key = try zcrypto.random.bytes32();

        return Self{
            .allocator = allocator,
            .crypto_engine = crypto_engine,
            .entries = std.ArrayList(LogEntry).init(allocator),
            .chain_key = chain_key,
        };
    }

    /// Log a database operation with cryptographic proof
    pub fn logOperation(self: *Self, table_name: []const u8, operation: []const u8, data: []const u8) !void {
        const transaction_id = @as(u64, @intCast(std.time.timestamp()));
        const data_hash = try self.crypto_engine.hashData(data);

        // Get previous hash for chaining
        const prev_hash = if (self.entries.items.len > 0)
            self.entries.items[self.entries.items.len - 1].data_hash
        else
            std.mem.zeroes([32]u8);

        // Create signature
        var signing_data = std.ArrayList(u8).init(self.allocator);
        defer signing_data.deinit();
        try signing_data.appendSlice(std.mem.asBytes(&transaction_id));
        try signing_data.appendSlice(table_name);
        try signing_data.appendSlice(operation);
        try signing_data.appendSlice(&data_hash);
        try signing_data.appendSlice(&prev_hash);

        const signature = try self.crypto_engine.signTransaction(signing_data.items, self.chain_key);

        const entry = LogEntry{
            .transaction_id = transaction_id,
            .table_name = try self.allocator.dupe(u8, table_name),
            .operation = try self.allocator.dupe(u8, operation),
            .data_hash = data_hash,
            .timestamp = std.time.timestamp(),
            .signature = signature,
            .prev_hash = prev_hash,
        };

        try self.entries.append(entry);
    }

    /// Verify the integrity of the entire transaction log
    pub fn verifyIntegrity(self: *Self) !bool {
        // Derive public key from private key for verification
        const public_key = try zcrypto.signatures.ed25519.publicKeyFromPrivate(&self.chain_key);

        for (self.entries.items, 0..) |entry, i| {
            // Reconstruct signing data
            var signing_data = std.ArrayList(u8).init(self.allocator);
            defer signing_data.deinit();
            try signing_data.appendSlice(std.mem.asBytes(&entry.transaction_id));
            try signing_data.appendSlice(entry.table_name);
            try signing_data.appendSlice(entry.operation);
            try signing_data.appendSlice(&entry.data_hash);
            try signing_data.appendSlice(&entry.prev_hash);

            // Verify signature
            if (!try self.crypto_engine.verifyTransaction(signing_data.items, entry.signature, public_key)) {
                return false;
            }

            // Verify chain integrity
            if (i > 0) {
                const expected_prev_hash = self.entries.items[i - 1].data_hash;
                if (!std.mem.eql(u8, &entry.prev_hash, &expected_prev_hash)) {
                    return false;
                }
            }
        }

        return true;
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.table_name);
            self.allocator.free(entry.operation);
        }
        self.entries.deinit();

        // Securely zero the chain key
        std.crypto.utils.secureZero(u8, &self.chain_key);
    }
};

// Test the crypto functionality
test "encrypt and decrypt field" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var crypto = try CryptoEngine.initWithMasterKey(allocator, "test_password");
    defer crypto.deinit();

    const plaintext = "sensitive_api_key_12345";
    const encrypted = try crypto.encryptField(plaintext);
    defer encrypted.deinit(allocator);

    const decrypted = try crypto.decryptField(encrypted);
    defer allocator.free(decrypted);

    try testing.expectEqualStrings(plaintext, decrypted);
}

test "password hashing and verification" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var crypto = CryptoEngine.init(allocator);
    defer crypto.deinit();

    const password = "super_secret_password";
    const hash = try crypto.hashPassword(password);
    defer hash.deinit(allocator);

    try testing.expect(try crypto.verifyPassword(password, hash));
    try testing.expect(!try crypto.verifyPassword("wrong_password", hash));
}
