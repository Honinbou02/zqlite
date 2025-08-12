# 🔗 ZQLite Integration Guide

> **ZQLite v1.3.0** - Comprehensive crypto/blockchain database with multi-wallet support, digital signatures, and advanced ledger capabilities.

This guide provides detailed integration instructions for crypto projects, traditional applications, and the broader Zig ecosystem.

---

## 📋 **Table of Contents**

- [Quick Start](#quick-start)
- [Core Crypto Features](#core-crypto-features)
- [Wallet Integration (zwallet)](#wallet-integration-zwallet)
- [Digital Signatures (zsig)](#digital-signatures-zsig)
- [Ledger Integration (zledger)](#ledger-integration-zledger)
- [Traditional Database Usage](#traditional-database-usage)
- [Zig Project Integration](#zig-project-integration)
- [API Reference](#api-reference)
- [Security Best Practices](#security-best-practices)
- [Performance Optimization](#performance-optimization)
- [Examples](#examples)

---

## 🚀 **Quick Start**

### Installation

```bash
# Clone the repository
git clone https://github.com/ghostkellz/zqlite.git
cd zqlite

# Build the library
zig build

# Run tests
zig build test
```

### Basic Integration

```zig
// Add to your build.zig
const zqlite = @import("path/to/zqlite");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "your-project",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    exe.addModule("zqlite", zqlite.module(b));
    exe.linkLibrary(zqlite.artifact(b));
}
```

### Simple Usage

```zig
const std = @import("std");
const zqlite = @import("zqlite");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize database
    var db = try zqlite.Database.init(allocator, "myapp.db");
    defer db.deinit();

    // Create table with crypto features
    try db.execute(
        \\CREATE TABLE transactions (
        \\    id INTEGER PRIMARY KEY,
        \\    hash TEXT NOT NULL,
        \\    amount REAL NOT NULL,
        \\    created_at TEXT DEFAULT (datetime('now'))
        \\);
    );

    // Insert data
    try db.execute("INSERT INTO transactions (hash, amount) VALUES ('0xabc123', 1.5);");
    
    // Query data
    const result = try db.query("SELECT * FROM transactions;");
    defer result.deinit();
}
```

---

## 🔐 **Core Crypto Features**

### Multi-Wallet Management

```zig
const wallet = @import("zqlite").wallet;

// Initialize wallet manager
var wallet_manager = wallet.WalletManager.init(allocator);
defer wallet_manager.deinit();

// Create HD wallet
const mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const btc_wallet = try wallet.HDWallet.createWallet(
    allocator,
    "Bitcoin Wallet",
    wallet.CoinTypes.BITCOIN,
    mnemonic,
    "secure_password"
);

// Derive addresses
const receive_addr = try btc_wallet.getReceiveAddress(0, 0); // m/44'/0'/0'/0/0
const change_addr = try btc_wallet.getChangeAddress(0, 0);   // m/44'/0'/0'/1/0
```

### Encrypted Storage

```zig
const encrypted_storage = @import("zqlite").wallet.encrypted_storage;

// Store encrypted seed
var storage = encrypted_storage.WalletStorage.init(allocator);
defer storage.deinit();

try storage.storeWallet(
    "my_wallet_id",
    "My Secure Wallet",
    wallet.CoinTypes.ETHEREUM,
    mnemonic,
    "master_password"
);

// Retrieve and decrypt
var decrypted_seed = try storage.loadWallet("my_wallet_id", "master_password");
defer decrypted_seed.deinit();
```

### Key Management

```zig
const key_manager = @import("zqlite").wallet.key_manager;

// Initialize key manager
var km = key_manager.KeyManager.init(allocator);
defer km.deinit();

// Create master key
try km.createMasterKey("wallet_1", .ED25519, mnemonic, "password");

// Derive and use keys
const path = [_]u32{ 44, 60, 0, 0, 0 }; // Ethereum derivation path
const signature = try km.signMessage("wallet_1", &path, "Hello, World!");
defer allocator.free(signature);
```

---

## 💼 **Wallet Integration (zwallet)**

### Project Structure Integration

```zig
// zwallet/src/main.zig
const std = @import("std");
const zqlite = @import("zqlite");

pub const ZWallet = struct {
    db: zqlite.Database,
    wallet_manager: zqlite.wallet.WalletManager,
    key_manager: zqlite.wallet.key_manager.KeyManager,
    
    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !ZWallet {
        return ZWallet{
            .db = try zqlite.Database.init(allocator, db_path),
            .wallet_manager = zqlite.wallet.WalletManager.init(allocator),
            .key_manager = zqlite.wallet.key_manager.KeyManager.init(allocator),
        };
    }
    
    pub fn deinit(self: *ZWallet) void {
        self.db.deinit();
        self.wallet_manager.deinit();
        self.key_manager.deinit();
    }
    
    pub fn createWallet(self: *ZWallet, name: []const u8, coin_type: u32) ![]const u8 {
        // Generate new mnemonic
        const mnemonic = try zqlite.wallet.HDWallet.generateMnemonic(
            self.db.allocator, 
            256
        );
        defer self.db.allocator.free(mnemonic);
        
        // Create wallet
        const wallet = try zqlite.wallet.HDWallet.createWallet(
            self.db.allocator,
            name,
            coin_type,
            mnemonic,
            ""
        );
        
        // Store in database
        try self.db.execute(
            \\INSERT INTO wallets (id, name, coin_type, created_at) 
            \\VALUES (?, ?, ?, datetime('now'));
        );
        
        return wallet.id;
    }
    
    pub fn getBalance(self: *ZWallet, wallet_id: []const u8) !f64 {
        const result = try self.db.query(
            \\SELECT SUM(amount) FROM transactions 
            \\WHERE wallet_id = ? AND type = 'credit';
        );
        defer result.deinit();
        
        if (result.rows.items.len > 0) {
            switch (result.rows.items[0].values[0]) {
                .Real => |balance| return balance,
                .Integer => |balance| return @floatFromInt(balance),
                else => return 0.0,
            }
        }
        return 0.0;
    }
    
    pub fn sendTransaction(self: *ZWallet, from_wallet: []const u8, to_address: []const u8, amount: f64) ![]const u8 {
        // Derive signing key
        const path = [_]u32{ 44, 0, 0, 0, 0 };
        const tx_hash = try self.key_manager.signMessage(from_wallet, &path, to_address);
        defer self.db.allocator.free(tx_hash);
        
        // Record transaction
        try self.db.execute(
            \\INSERT INTO transactions (wallet_id, to_address, amount, hash, created_at) 
            \\VALUES (?, ?, ?, ?, datetime('now'));
        );
        
        return self.db.allocator.dupe(u8, tx_hash);
    }
};
```

### Database Schema Setup

```sql
-- Initialize wallet tables
CREATE TABLE wallets (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    coin_type INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    last_access TEXT DEFAULT (datetime('now'))
);

CREATE TABLE transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    wallet_id TEXT NOT NULL,
    to_address TEXT NOT NULL,
    amount REAL NOT NULL,
    hash TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    created_at TEXT DEFAULT (datetime('now')),
    confirmed_at TEXT,
    FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);

CREATE TABLE addresses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    wallet_id TEXT NOT NULL,
    address TEXT NOT NULL,
    derivation_path TEXT NOT NULL,
    address_type TEXT NOT NULL, -- 'receive' or 'change'
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

---

## ✍️ **Digital Signatures (zsig)**

### Multi-Signature Support

```zig
// zsig/src/multisig.zig
const std = @import("std");
const zqlite = @import("zqlite");

pub const MultiSig = struct {
    db: zqlite.Database,
    key_manager: zqlite.wallet.key_manager.KeyManager,
    
    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !MultiSig {
        var db = try zqlite.Database.init(allocator, db_path);
        
        // Initialize multisig schema
        try db.execute(
            \\CREATE TABLE IF NOT EXISTS multisig_wallets (
            \\    id TEXT PRIMARY KEY,
            \\    name TEXT NOT NULL,
            \\    threshold INTEGER NOT NULL,
            \\    total_signers INTEGER NOT NULL,
            \\    created_at TEXT DEFAULT (datetime('now'))
            \\);
        );
        
        try db.execute(
            \\CREATE TABLE IF NOT EXISTS multisig_signers (
            \\    wallet_id TEXT NOT NULL,
            \\    signer_id TEXT NOT NULL,
            \\    public_key TEXT NOT NULL,
            \\    added_at TEXT DEFAULT (datetime('now')),
            \\    PRIMARY KEY (wallet_id, signer_id),
            \\    FOREIGN KEY (wallet_id) REFERENCES multisig_wallets(id)
            \\);
        );
        
        return MultiSig{
            .db = db,
            .key_manager = zqlite.wallet.key_manager.KeyManager.init(allocator),
        };
    }
    
    pub fn createMultiSigWallet(self: *MultiSig, name: []const u8, threshold: u32, signers: []const []const u8) ![]const u8 {
        const wallet_id = try std.fmt.allocPrint(self.db.allocator, "multisig_{d}", .{std.time.timestamp()});
        
        // Create wallet
        try self.db.execute(
            \\INSERT INTO multisig_wallets (id, name, threshold, total_signers) 
            \\VALUES (?, ?, ?, ?);
        );
        
        // Add signers
        for (signers, 0..) |signer, i| {
            try self.db.execute(
                \\INSERT INTO multisig_signers (wallet_id, signer_id, public_key) 
                \\VALUES (?, ?, ?);
            );
        }
        
        return wallet_id;
    }
    
    pub fn signTransaction(self: *MultiSig, wallet_id: []const u8, signer_id: []const u8, message: []const u8) ![]const u8 {
        // Verify signer is authorized
        const result = try self.db.query(
            \\SELECT COUNT(*) FROM multisig_signers 
            \\WHERE wallet_id = ? AND signer_id = ?;
        );
        defer result.deinit();
        
        if (result.rows.items.len == 0) {
            return error.UnauthorizedSigner;
        }
        
        // Sign message
        const path = [_]u32{ 44, 0, 0, 0, 0 };
        return self.key_manager.signMessage(signer_id, &path, message);
    }
    
    pub fn verifyMultiSig(self: *MultiSig, wallet_id: []const u8, message: []const u8, signatures: []const []const u8) !bool {
        const wallet_info = try self.db.query(
            \\SELECT threshold, total_signers FROM multisig_wallets WHERE id = ?;
        );
        defer wallet_info.deinit();
        
        if (wallet_info.rows.items.len == 0) {
            return error.WalletNotFound;
        }
        
        const threshold = wallet_info.rows.items[0].values[0].Integer;
        
        // Verify signatures meet threshold
        var valid_signatures: u32 = 0;
        for (signatures) |signature| {
            // Verify each signature (simplified)
            if (signature.len > 0) {
                valid_signatures += 1;
            }
        }
        
        return valid_signatures >= threshold;
    }
};
```

### Document Signing

```zig
// zsig/src/document.zig
pub const DocumentSigner = struct {
    db: zqlite.Database,
    key_manager: zqlite.wallet.key_manager.KeyManager,
    
    pub fn signDocument(self: *DocumentSigner, document_hash: []const u8, signer_id: []const u8) ![]const u8 {
        const signature = try self.key_manager.signMessage(signer_id, &[_]u32{ 44, 0, 0, 0, 0 }, document_hash);
        
        // Store signature in database
        try self.db.execute(
            \\INSERT INTO document_signatures (document_hash, signer_id, signature, created_at) 
            \\VALUES (?, ?, ?, datetime('now'));
        );
        
        return signature;
    }
    
    pub fn verifyDocument(self: *DocumentSigner, document_hash: []const u8, signature: []const u8, public_key: []const u8) !bool {
        const pub_key = zqlite.wallet.key_manager.KeyManager.PublicKey{
            .key_type = .ED25519,
            .key_data = try self.db.allocator.dupe(u8, public_key),
        };
        defer pub_key.deinit(self.db.allocator);
        
        return self.key_manager.verifySignature(pub_key, document_hash, signature);
    }
};
```

---

## 📊 **Ledger Integration (zledger)**

### Double-Entry Accounting

```zig
// zledger/src/accounting.zig
const std = @import("std");
const zqlite = @import("zqlite");

pub const Ledger = struct {
    db: zqlite.Database,
    
    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !Ledger {
        var db = try zqlite.Database.init(allocator, db_path);
        
        // Initialize accounting schema
        try db.execute(
            \\CREATE TABLE IF NOT EXISTS accounts (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    code TEXT UNIQUE NOT NULL,
            \\    name TEXT NOT NULL,
            \\    account_type TEXT NOT NULL, -- 'asset', 'liability', 'equity', 'revenue', 'expense'
            \\    parent_id INTEGER,
            \\    created_at TEXT DEFAULT (datetime('now')),
            \\    FOREIGN KEY (parent_id) REFERENCES accounts(id)
            \\);
        );
        
        try db.execute(
            \\CREATE TABLE IF NOT EXISTS journal_entries (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    transaction_id TEXT NOT NULL,
            \\    description TEXT NOT NULL,
            \\    date TEXT DEFAULT (date('now')),
            \\    created_at TEXT DEFAULT (datetime('now'))
            \\);
        );
        
        try db.execute(
            \\CREATE TABLE IF NOT EXISTS journal_lines (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    journal_entry_id INTEGER NOT NULL,
            \\    account_id INTEGER NOT NULL,
            \\    debit_amount REAL DEFAULT 0,
            \\    credit_amount REAL DEFAULT 0,
            \\    description TEXT,
            \\    created_at TEXT DEFAULT (datetime('now')),
            \\    FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id),
            \\    FOREIGN KEY (account_id) REFERENCES accounts(id)
            \\);
        );
        
        return Ledger{ .db = db };
    }
    
    pub fn createAccount(self: *Ledger, code: []const u8, name: []const u8, account_type: []const u8) !u64 {
        try self.db.execute(
            \\INSERT INTO accounts (code, name, account_type) VALUES (?, ?, ?);
        );
        
        const result = try self.db.query("SELECT last_insert_rowid();");
        defer result.deinit();
        
        return @intCast(result.rows.items[0].values[0].Integer);
    }
    
    pub fn recordTransaction(self: *Ledger, transaction_id: []const u8, description: []const u8, entries: []const JournalEntry) !void {
        // Create journal entry
        try self.db.execute(
            \\INSERT INTO journal_entries (transaction_id, description) VALUES (?, ?);
        );
        
        const journal_id_result = try self.db.query("SELECT last_insert_rowid();");
        defer journal_id_result.deinit();
        const journal_id = journal_id_result.rows.items[0].values[0].Integer;
        
        // Add journal lines
        var total_debits: f64 = 0;
        var total_credits: f64 = 0;
        
        for (entries) |entry| {
            try self.db.execute(
                \\INSERT INTO journal_lines (journal_entry_id, account_id, debit_amount, credit_amount, description) 
                \\VALUES (?, ?, ?, ?, ?);
            );
            
            total_debits += entry.debit_amount;
            total_credits += entry.credit_amount;
        }
        
        // Verify accounting equation
        if (std.math.fabs(total_debits - total_credits) > 0.01) {
            return error.UnbalancedTransaction;
        }
    }
    
    pub fn getAccountBalance(self: *Ledger, account_id: u64) !f64 {
        const result = try self.db.query(
            \\SELECT 
            \\    SUM(debit_amount) as total_debits,
            \\    SUM(credit_amount) as total_credits
            \\FROM journal_lines 
            \\WHERE account_id = ?;
        );
        defer result.deinit();
        
        if (result.rows.items.len > 0) {
            const row = result.rows.items[0];
            const debits = if (row.values[0] == .Real) row.values[0].Real else 0;
            const credits = if (row.values[1] == .Real) row.values[1].Real else 0;
            return debits - credits;
        }
        
        return 0.0;
    }
    
    pub fn generateTrialBalance(self: *Ledger) ![]AccountBalance {
        const result = try self.db.query(
            \\SELECT 
            \\    a.code,
            \\    a.name,
            \\    a.account_type,
            \\    SUM(jl.debit_amount) as total_debits,
            \\    SUM(jl.credit_amount) as total_credits
            \\FROM accounts a
            \\LEFT JOIN journal_lines jl ON a.id = jl.account_id
            \\GROUP BY a.id, a.code, a.name, a.account_type
            \\ORDER BY a.code;
        );
        defer result.deinit();
        
        var balances = std.ArrayList(AccountBalance).init(self.db.allocator);
        for (result.rows.items) |row| {
            const debits = if (row.values[3] == .Real) row.values[3].Real else 0;
            const credits = if (row.values[4] == .Real) row.values[4].Real else 0;
            
            try balances.append(AccountBalance{
                .code = try self.db.allocator.dupe(u8, row.values[0].Text),
                .name = try self.db.allocator.dupe(u8, row.values[1].Text),
                .account_type = try self.db.allocator.dupe(u8, row.values[2].Text),
                .balance = debits - credits,
            });
        }
        
        return balances.toOwnedSlice();
    }
};

pub const JournalEntry = struct {
    account_id: u64,
    debit_amount: f64,
    credit_amount: f64,
    description: []const u8,
};

pub const AccountBalance = struct {
    code: []const u8,
    name: []const u8,
    account_type: []const u8,
    balance: f64,
    
    pub fn deinit(self: AccountBalance, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.name);
        allocator.free(self.account_type);
    }
};
```

### Crypto Portfolio Tracking

```zig
// zledger/src/portfolio.zig
pub const Portfolio = struct {
    db: zqlite.Database,
    
    pub fn trackCryptoTransaction(self: *Portfolio, asset: []const u8, amount: f64, price: f64, tx_type: []const u8) !void {
        // Record the transaction
        try self.db.execute(
            \\INSERT INTO crypto_transactions (asset, amount, price, tx_type, created_at) 
            \\VALUES (?, ?, ?, ?, datetime('now'));
        );
        
        // Update portfolio balance
        const current_balance = try self.getAssetBalance(asset);
        const new_balance = if (std.mem.eql(u8, tx_type, "buy")) 
            current_balance + amount 
        else 
            current_balance - amount;
            
        try self.db.execute(
            \\INSERT OR REPLACE INTO portfolio_balances (asset, balance, last_updated) 
            \\VALUES (?, ?, datetime('now'));
        );
    }
    
    pub fn calculatePnL(self: *Portfolio, asset: []const u8) !f64 {
        const result = try self.db.query(
            \\SELECT 
            \\    SUM(CASE WHEN tx_type = 'buy' THEN amount * price ELSE -amount * price END) as cost_basis,
            \\    SUM(CASE WHEN tx_type = 'buy' THEN amount ELSE -amount END) as balance
            \\FROM crypto_transactions 
            \\WHERE asset = ?;
        );
        defer result.deinit();
        
        if (result.rows.items.len > 0) {
            const cost_basis = result.rows.items[0].values[0].Real;
            const balance = result.rows.items[0].values[1].Real;
            
            // Get current price (simplified)
            const current_price = try self.getCurrentPrice(asset);
            const current_value = balance * current_price;
            
            return current_value - cost_basis;
        }
        
        return 0.0;
    }
    
    fn getCurrentPrice(self: *Portfolio, asset: []const u8) !f64 {
        // Simplified price lookup - integrate with price APIs
        _ = self;
        _ = asset;
        return 50000.0; // Mock price
    }
    
    fn getAssetBalance(self: *Portfolio, asset: []const u8) !f64 {
        const result = try self.db.query(
            \\SELECT balance FROM portfolio_balances WHERE asset = ?;
        );
        defer result.deinit();
        
        if (result.rows.items.len > 0) {
            return result.rows.items[0].values[0].Real;
        }
        
        return 0.0;
    }
};
```

---

## 🗄️ **Traditional Database Usage**

### Standard SQL Operations

```zig
const std = @import("std");
const zqlite = @import("zqlite");

pub fn traditionalExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = try zqlite.Database.init(allocator, "app.db");
    defer db.deinit();

    // Create tables
    try db.execute(
        \\CREATE TABLE users (
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    username TEXT UNIQUE NOT NULL,
        \\    email TEXT UNIQUE NOT NULL,
        \\    password_hash TEXT NOT NULL,
        \\    created_at TEXT DEFAULT (datetime('now')),
        \\    last_login TEXT
        \\);
    );

    try db.execute(
        \\CREATE TABLE posts (
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    user_id INTEGER NOT NULL,
        \\    title TEXT NOT NULL,
        \\    content TEXT NOT NULL,
        \\    created_at TEXT DEFAULT (datetime('now')),
        \\    updated_at TEXT DEFAULT (datetime('now')),
        \\    FOREIGN KEY (user_id) REFERENCES users(id)
        \\);
    );

    // Insert data
    try db.execute(
        \\INSERT INTO users (username, email, password_hash) 
        \\VALUES ('john_doe', 'john@example.com', 'hashed_password_123');
    );

    // Query with joins
    const result = try db.query(
        \\SELECT 
        \\    u.username,
        \\    p.title,
        \\    p.created_at
        \\FROM users u
        \\JOIN posts p ON u.id = p.user_id
        \\WHERE u.username = 'john_doe'
        \\ORDER BY p.created_at DESC;
    );
    defer result.deinit();

    // Process results
    for (result.rows.items) |row| {
        const username = row.values[0].Text;
        const title = row.values[1].Text;
        const created_at = row.values[2].Text;
        
        std.log.info("User: {s}, Post: {s}, Created: {s}", .{ username, title, created_at });
    }
}
```

### Advanced Features

```zig
// Transactions
try db.beginTransaction();
defer db.rollback() catch {};

try db.execute("INSERT INTO users (username, email) VALUES ('user1', 'user1@example.com');");
try db.execute("INSERT INTO posts (user_id, title) VALUES (1, 'First Post');");

try db.commit();

// Prepared statements
var stmt = try db.prepare("SELECT * FROM users WHERE id = ?");
defer stmt.deinit();

try stmt.bind(0, @as(i64, 1));
const result = try stmt.execute();
defer result.deinit();

// Batch operations
const batch_sql = [_][]const u8{
    "INSERT INTO users (username, email) VALUES ('user2', 'user2@example.com');",
    "INSERT INTO users (username, email) VALUES ('user3', 'user3@example.com');",
    "INSERT INTO users (username, email) VALUES ('user4', 'user4@example.com');",
};

try db.executeBatch(&batch_sql);
```

---

## 🔧 **Zig Project Integration**

### Build Configuration

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add ZQLite dependency
    const zqlite_dep = b.dependency("zqlite", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Link ZQLite
    exe.root_module.addImport("zqlite", zqlite_dep.module("zqlite"));
    exe.linkLibrary(zqlite_dep.artifact("zqlite"));

    b.installArtifact(exe);
}
```

### Module System Integration

```zig
// src/database.zig
const std = @import("std");
const zqlite = @import("zqlite");

pub const AppDatabase = struct {
    db: zqlite.Database,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !AppDatabase {
        var db = try zqlite.Database.init(allocator, db_path);
        
        // Initialize app-specific schema
        try db.execute(@embedFile("schema.sql"));
        
        return AppDatabase{
            .db = db,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *AppDatabase) void {
        self.db.deinit();
    }
    
    // App-specific methods
    pub fn createUser(self: *AppDatabase, username: []const u8, email: []const u8) !u64 {
        try self.db.execute(
            \\INSERT INTO users (username, email, created_at) 
            \\VALUES (?, ?, datetime('now'));
        );
        
        const result = try self.db.query("SELECT last_insert_rowid();");
        defer result.deinit();
        
        return @intCast(result.rows.items[0].values[0].Integer);
    }
};
```

### Error Handling Integration

```zig
// src/errors.zig
const std = @import("std");
const zqlite = @import("zqlite");

pub const AppError = error{
    DatabaseError,
    UserNotFound,
    InvalidCredentials,
    DuplicateUser,
} || zqlite.Error;

pub fn handleDatabaseError(err: anyerror) AppError {
    return switch (err) {
        zqlite.Error.TableNotFound => AppError.DatabaseError,
        zqlite.Error.ConstraintViolation => AppError.DuplicateUser,
        else => AppError.DatabaseError,
    };
}
```

---

## 📚 **API Reference**

### Core Database API

```zig
// Database initialization
pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !Database
pub fn deinit(self: *Database) void

// SQL execution
pub fn execute(self: *Database, sql: []const u8) !void
pub fn query(self: *Database, sql: []const u8) !QueryResult
pub fn prepare(self: *Database, sql: []const u8) !PreparedStatement

// Transactions
pub fn beginTransaction(self: *Database) !void
pub fn commit(self: *Database) !void
pub fn rollback(self: *Database) !void

// Batch operations
pub fn executeBatch(self: *Database, statements: []const []const u8) !void
```

### Wallet API

```zig
// HD Wallet
pub fn createWallet(allocator: Allocator, name: []const u8, coin_type: u32, mnemonic: []const u8, passphrase: []const u8) !Wallet
pub fn deriveAddress(self: Wallet, account_index: u32, change: u32, address_index: u32) !ExtendedKey
pub fn getReceiveAddress(self: Wallet, account_index: u32, address_index: u32) !ExtendedKey
pub fn getChangeAddress(self: Wallet, account_index: u32, address_index: u32) !ExtendedKey

// Encrypted Storage
pub fn storeWallet(self: *WalletStorage, wallet_id: []const u8, name: []const u8, coin_type: u32, mnemonic: []const u8, password: []const u8) !void
pub fn loadWallet(self: *WalletStorage, wallet_id: []const u8, password: []const u8) !SecureString
pub fn changePassword(self: *WalletStorage, wallet_id: []const u8, old_password: []const u8, new_password: []const u8) !void

// Key Management
pub fn createMasterKey(self: *KeyManager, wallet_id: []const u8, key_type: KeyType, mnemonic: []const u8, password: []const u8) !void
pub fn deriveKey(self: *KeyManager, wallet_id: []const u8, path: []const u32) !PrivateKey
pub fn signMessage(self: *KeyManager, wallet_id: []const u8, path: []const u32, message: []const u8) ![]u8
pub fn verifySignature(self: *KeyManager, public_key: PublicKey, message: []const u8, signature: []const u8) !bool
```

### Function Evaluation API

```zig
// Datetime functions
pub fn evaluateFunction(self: *FunctionEvaluator, function_call: ast.FunctionCall) !storage.Value

// Supported functions:
// - NOW()
// - DATETIME('now')
// - UNIXEPOCH()
// - STRFTIME('%s', 'now')
// - DATE('now')
// - TIME('now')
// - JULIANDAY()
```

---

## 🛡️ **Security Best Practices**

### 1. **Key Management**

```zig
// ✅ DO: Use secure random generation
const seed = crypto.random.bytes(32);

// ✅ DO: Zero out sensitive data
defer std.mem.set(u8, &seed, 0);

// ❌ DON'T: Store keys in plain text
const private_key = "clear_text_key"; // Never do this

// ✅ DO: Use encrypted storage
const encrypted_key = try encryptWithMasterPassword(private_key, master_password);
```

### 2. **Database Security**

```zig
// ✅ DO: Use prepared statements
var stmt = try db.prepare("SELECT * FROM users WHERE id = ?");
try stmt.bind(0, user_id);

// ❌ DON'T: Use string concatenation
const sql = try std.fmt.allocPrint(allocator, "SELECT * FROM users WHERE id = {}", .{user_id});
```

### 3. **Password Handling**

```zig
// ✅ DO: Use strong key derivation
const iterations = 100000;
const salt = crypto.random.bytes(32);
crypto.pwhash.pbkdf2(&key, password, &salt, iterations, crypto.auth.hmac.HmacSha256);

// ✅ DO: Clear passwords from memory
defer std.mem.set(u8, password, 0);
```

### 4. **Error Handling**

```zig
// ✅ DO: Handle crypto errors properly
const signature = key.sign(message) catch |err| switch (err) {
    error.InvalidKey => return error.CryptoError,
    error.SigningFailed => return error.CryptoError,
    else => return err,
};

// ✅ DO: Don't expose sensitive information in errors
return error.AuthenticationFailed; // Instead of "Invalid password for user X"
```

---

## ⚡ **Performance Optimization**

### 1. **Database Optimization**

```zig
// Create indexes for frequently queried columns
try db.execute("CREATE INDEX idx_users_email ON users(email);");
try db.execute("CREATE INDEX idx_transactions_wallet_id ON transactions(wallet_id);");
try db.execute("CREATE INDEX idx_transactions_created_at ON transactions(created_at);");

// Use transactions for bulk operations
try db.beginTransaction();
for (data) |item| {
    try db.execute("INSERT INTO table VALUES (?, ?);");
}
try db.commit();

// Use prepared statements for repeated queries
var stmt = try db.prepare("INSERT INTO transactions (wallet_id, amount) VALUES (?, ?);");
defer stmt.deinit();

for (transactions) |tx| {
    try stmt.bind(0, tx.wallet_id);
    try stmt.bind(1, tx.amount);
    try stmt.execute();
    stmt.reset();
}
```

### 2. **Memory Management**

```zig
// Use arena allocators for temporary operations
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const temp_allocator = arena.allocator();

// Batch allocations
const batch_size = 1000;
var batch = try temp_allocator.alloc(Transaction, batch_size);

// Reuse objects where possible
var key_cache = std.HashMap([]const u8, PrivateKey, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
defer key_cache.deinit();
```

### 3. **Crypto Performance**

```zig
// Precompute frequently used keys
const master_key = try deriveMasterKey(seed);
const address_keys = try deriveAddressKeys(master_key, 0..100);

// Use batch signature verification
const signatures = try verifyBatchSignatures(messages, signatures, public_keys);

// Cache public keys
var pubkey_cache = std.HashMap([]const u8, PublicKey, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
```

---

## 🔍 **Examples**

### Complete Wallet Application

```zig
// examples/wallet_app.zig
const std = @import("std");
const zqlite = @import("zqlite");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize database
    var db = try zqlite.Database.init(allocator, "wallet.db");
    defer db.deinit();

    // Initialize wallet components
    var wallet_manager = zqlite.wallet.WalletManager.init(allocator);
    defer wallet_manager.deinit();

    var key_manager = zqlite.wallet.key_manager.KeyManager.init(allocator);
    defer key_manager.deinit();

    // Create wallet schema
    try db.execute(@embedFile("wallet_schema.sql"));

    // Create a new wallet
    const mnemonic = try zqlite.wallet.HDWallet.generateMnemonic(allocator, 256);
    defer allocator.free(mnemonic);

    const wallet = try zqlite.wallet.HDWallet.createWallet(
        allocator,
        "My Bitcoin Wallet",
        zqlite.wallet.CoinTypes.BITCOIN,
        mnemonic,
        "secure_password"
    );

    // Store wallet
    try wallet_manager.addWallet(wallet);

    // Create master key
    try key_manager.createMasterKey(wallet.id, .SECP256K1, mnemonic, "secure_password");

    // Generate addresses
    const receive_addr = try wallet.getReceiveAddress(0, 0);
    const change_addr = try wallet.getChangeAddress(0, 0);

    std.log.info("Wallet created: {s}", .{wallet.id});
    std.log.info("Receive address: {x}", .{receive_addr.key});
    std.log.info("Change address: {x}", .{change_addr.key});

    // Simulate a transaction
    const tx_data = "transfer_to_address_xyz";
    const signature = try key_manager.signMessage(wallet.id, &[_]u32{ 44, 0, 0, 0, 0 }, tx_data);
    defer allocator.free(signature);

    // Store transaction
    try db.execute(
        \\INSERT INTO transactions (wallet_id, to_address, amount, signature, created_at) 
        \\VALUES (?, ?, ?, ?, datetime('now'));
    );

    std.log.info("Transaction signed and stored");
}
```

### Multi-Signature Wallet

```zig
// examples/multisig_wallet.zig
const std = @import("std");
const zqlite = @import("zqlite");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = try zqlite.Database.init(allocator, "multisig.db");
    defer db.deinit();

    var key_manager = zqlite.wallet.key_manager.KeyManager.init(allocator);
    defer key_manager.deinit();

    // Create multisig schema
    try db.execute(@embedFile("multisig_schema.sql"));

    // Create signers
    const signers = [_][]const u8{ "signer1", "signer2", "signer3" };
    
    for (signers) |signer| {
        const mnemonic = try zqlite.wallet.HDWallet.generateMnemonic(allocator, 256);
        defer allocator.free(mnemonic);
        
        try key_manager.createMasterKey(signer, .SECP256K1, mnemonic, "password");
    }

    // Create 2-of-3 multisig wallet
    const wallet_id = try std.fmt.allocPrint(allocator, "multisig_{d}", .{std.time.timestamp()});
    defer allocator.free(wallet_id);

    try db.execute(
        \\INSERT INTO multisig_wallets (id, name, threshold, total_signers) 
        \\VALUES (?, ?, ?, ?);
    );

    // Add signers to wallet
    for (signers) |signer| {
        const public_key = try key_manager.exportPublicKey(signer, &[_]u32{ 44, 0, 0, 0, 0 });
        defer public_key.deinit(allocator);

        try db.execute(
            \\INSERT INTO multisig_signers (wallet_id, signer_id, public_key) 
            \\VALUES (?, ?, ?);
        );
    }

    // Sign transaction with multiple signers
    const tx_message = "send_100_btc_to_address";
    var signatures = std.ArrayList([]u8).init(allocator);
    defer signatures.deinit();

    // Sign with first two signers (meets 2-of-3 threshold)
    for (signers[0..2]) |signer| {
        const signature = try key_manager.signMessage(signer, &[_]u32{ 44, 0, 0, 0, 0 }, tx_message);
        try signatures.append(signature);
    }

    // Verify transaction has sufficient signatures
    const threshold_met = signatures.items.len >= 2;
    std.log.info("Transaction threshold met: {}", .{threshold_met});

    // Store transaction
    try db.execute(
        \\INSERT INTO multisig_transactions (wallet_id, message, signatures, created_at) 
        \\VALUES (?, ?, ?, datetime('now'));
    );

    std.log.info("Multisig transaction complete");
}
```

### DeFi Portfolio Tracker

```zig
// examples/defi_portfolio.zig
const std = @import("std");
const zqlite = @import("zqlite");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = try zqlite.Database.init(allocator, "portfolio.db");
    defer db.deinit();

    // Create portfolio schema
    try db.execute(@embedFile("portfolio_schema.sql"));

    // Track various DeFi positions
    const defi_positions = [_]struct {
        protocol: []const u8,
        asset: []const u8,
        amount: f64,
        apy: f64,
    }{
        .{ .protocol = "Uniswap", .asset = "ETH/USDC", .amount = 10.5, .apy = 12.5 },
        .{ .protocol = "Compound", .asset = "USDC", .amount = 5000.0, .apy = 8.2 },
        .{ .protocol = "Aave", .asset = "WETH", .amount = 2.3, .apy = 6.8 },
    };

    for (defi_positions) |position| {
        try db.execute(
            \\INSERT INTO defi_positions (protocol, asset, amount, apy, created_at) 
            \\VALUES (?, ?, ?, ?, datetime('now'));
        );
    }

    // Calculate total portfolio value
    const portfolio_value = try db.query(
        \\SELECT 
        \\    SUM(amount * current_price) as total_value,
        \\    COUNT(*) as position_count
        \\FROM defi_positions dp
        \\JOIN asset_prices ap ON dp.asset = ap.asset;
    );
    defer portfolio_value.deinit();

    // Generate yield report
    const yield_report = try db.query(
        \\SELECT 
        \\    protocol,
        \\    SUM(amount * apy / 100) as annual_yield,
        \\    AVG(apy) as avg_apy
        \\FROM defi_positions
        \\GROUP BY protocol
        \\ORDER BY annual_yield DESC;
    );
    defer yield_report.deinit();

    std.log.info("Portfolio analysis complete");
    
    for (yield_report.rows.items) |row| {
        const protocol = row.values[0].Text;
        const annual_yield = row.values[1].Real;
        const avg_apy = row.values[2].Real;
        
        std.log.info("Protocol: {s}, Annual Yield: {d:.2}, APY: {d:.2}%", .{ protocol, annual_yield, avg_apy });
    }
}
```

---

## 📞 **Support & Community**

### Getting Help

- **GitHub Issues**: [https://github.com/ghostkellz/zqlite/issues](https://github.com/ghostkellz/zqlite/issues)
- **Documentation**: [https://github.com/ghostkellz/zqlite/wiki](https://github.com/ghostkellz/zqlite/wiki)
- **Examples**: [https://github.com/ghostkellz/zqlite/tree/main/examples](https://github.com/ghostkellz/zqlite/tree/main/examples)

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

### License

ZQLite is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## 🔗 **Related Projects**

- **zwallet**: Multi-currency cryptocurrency wallet
- **zsig**: Digital signature and document signing platform
- **zledger**: Double-entry accounting and financial tracking
- **zcrypto**: Cryptographic utilities and primitives
- **znet**: Networking and communication protocols

---

*This integration guide provides comprehensive examples for integrating ZQLite into your crypto and traditional applications. For the latest updates and detailed API documentation, visit the [official repository](https://github.com/ghostkellz/zqlite).*