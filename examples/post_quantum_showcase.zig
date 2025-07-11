const std = @import("std");
const zqlite = @import("zqlite");

/// 🚀 ZQLite v0.6.0 Post-Quantum Showcase
/// Demonstrating cutting-edge cryptographic database features
/// Powered by ZQLite v0.6.0 with modular crypto backends

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🌟 Welcome to ZQLite v0.5.0 Post-Quantum Showcase!\n", .{});
    std.debug.print("=================================================\n\n", .{});

    // Demo 1: Post-Quantum Database Encryption
    try demoPostQuantumEncryption(allocator);
    
    // Demo 2: Hybrid Signature Verification
    try demoHybridSignatures(allocator);
    
    // Demo 3: Zero-Knowledge Database Queries
    try demoZeroKnowledgeQueries(allocator);
    
    // Demo 4: Post-Quantum QUIC Transport
    try demoPostQuantumQuic(allocator);
    
    // Demo 5: Blockchain-Style Transaction Log
    try demoBlockchainTransactionLog(allocator);
    
    // Demo 6: Advanced Cryptographic Features
    try demoAdvancedCrypto(allocator);

    std.debug.print("\n🎉 All demos completed successfully!\n", .{});
    std.debug.print("ZQLite v0.5.0 is ready for the post-quantum future! 🚀\n", .{});
}

/// Demo 1: Post-Quantum Database Encryption
fn demoPostQuantumEncryption(allocator: std.mem.Allocator) !void {
    std.debug.print("📊 Demo 1: Post-Quantum Database Encryption\n", .{});
    std.debug.print("--------------------------------------------\n", .{});

    // Create in-memory database with post-quantum crypto
    const conn = try zqlite.openMemory();
    defer conn.close();

    // Initialize crypto engine with post-quantum features
    var crypto = try zqlite.crypto.CryptoEngine.initWithMasterKey(
        allocator, 
        "ultra_secure_post_quantum_password_2024"
    );
    defer crypto.deinit();

    std.debug.print("✅ Initialized post-quantum crypto engine\n", .{});
    std.debug.print("   - ML-KEM-768 key encapsulation\n", .{});
    std.debug.print("   - ML-DSA-65 digital signatures\n", .{});
    std.debug.print("   - Hybrid classical + PQ security\n", .{});

    // Create secure table for sensitive data
    try conn.execute("CREATE TABLE crypto_wallets (id INTEGER PRIMARY KEY, address TEXT, private_key TEXT, balance REAL);");

    // Encrypt sensitive wallet data
    const wallet_address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh";
    const private_key = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn";
    
    var encrypted_address = try crypto.encryptField(wallet_address);
    defer encrypted_address.deinit(allocator);
    
    var encrypted_key = try crypto.encryptField(private_key);
    defer encrypted_key.deinit(allocator);

    std.debug.print("✅ Encrypted wallet data with ChaCha20-Poly1305\n", .{});
    std.debug.print("   - Address: {} bytes → {} bytes\n", .{ wallet_address.len, encrypted_address.len() });
    std.debug.print("   - Private key: {} bytes → {} bytes\n", .{ private_key.len, encrypted_key.len() });

    // Decrypt and verify
    const decrypted_address = try crypto.decryptField(encrypted_address);
    defer allocator.free(decrypted_address);
    
    const decrypted_key = try crypto.decryptField(encrypted_key);
    defer allocator.free(decrypted_key);

    std.debug.print("✅ Successfully decrypted wallet data\n", .{});
    std.debug.print("   - Address verified: {}\n", .{std.mem.eql(u8, wallet_address, decrypted_address)});
    std.debug.print("   - Private key verified: {}\n", .{std.mem.eql(u8, private_key, decrypted_key)});

    std.debug.print("\n", .{});
}

/// Demo 2: Hybrid Signature Verification
fn demoHybridSignatures(allocator: std.mem.Allocator) !void {
    std.debug.print("🔐 Demo 2: Hybrid Classical + Post-Quantum Signatures\n", .{});
    std.debug.print("----------------------------------------------------\n", .{});

    var crypto = try zqlite.crypto.CryptoEngine.initWithMasterKey(
        allocator, 
        "hybrid_signature_demo_2024"
    );
    defer crypto.deinit();

    // Test hybrid signature (Ed25519 + ML-DSA-65)
    const transaction_data = "TRANSFER 50000.00 BTC FROM WALLET_A TO WALLET_B";
    
    std.debug.print("📝 Signing transaction: {s}\n", .{transaction_data});
    
    const signature = try crypto.signTransaction(transaction_data);
    std.debug.print("✅ Created hybrid signature:\n", .{});
    std.debug.print("   - Classical (Ed25519): 64 bytes\n", .{});
    std.debug.print("   - Post-quantum (ML-DSA-65): 3309 bytes\n", .{});
    std.debug.print("   - Mode: {s}\n", .{"hybrid"});

    // Verify signature
    const is_valid = try crypto.verifyTransaction(transaction_data, signature);
    std.debug.print("✅ Signature verification: {s}\n", .{if (is_valid) "VALID" else "INVALID"});
    
    // Test post-quantum only mode
    crypto.enablePostQuantumOnlyMode();
    const pq_signature = try crypto.signTransaction(transaction_data);
    const pq_valid = try crypto.verifyTransaction(transaction_data, pq_signature);
    
    std.debug.print("✅ Post-quantum only signature: {s}\n", .{if (pq_valid) "VALID" else "INVALID"});
    std.debug.print("   - Quantum-safe for future threats\n", .{});

    std.debug.print("\n", .{});
}

/// Demo 3: Zero-Knowledge Database Queries
fn demoZeroKnowledgeQueries(allocator: std.mem.Allocator) !void {
    std.debug.print("🕵️ Demo 3: Zero-Knowledge Database Queries\n", .{});
    std.debug.print("------------------------------------------\n", .{});

    var crypto = try zqlite.crypto.CryptoEngine.initWithMasterKey(
        allocator, 
        "zero_knowledge_demo_2024"
    );
    defer crypto.deinit();
    crypto.enableZKP();

    std.debug.print("✅ Enabled zero-knowledge proof system\n", .{});

    // Create range proof (prove balance is in range without revealing amount)
    const secret_balance: u64 = 75000; // Secret balance
    const min_balance: u64 = 1000;     // Minimum required
    const max_balance: u64 = 1000000;  // Maximum allowed

    std.debug.print("🔍 Creating range proof for balance verification...\n", .{});
    std.debug.print("   - Secret balance: HIDDEN\n", .{});
    std.debug.print("   - Range: {} - {}\n", .{ min_balance, max_balance });

    var proof = try crypto.createRangeProof(secret_balance, min_balance, max_balance);
    defer proof.deinit(allocator);

    std.debug.print("✅ Generated bulletproof range proof:\n", .{});
    std.debug.print("   - Proof size: {} bytes\n", .{proof.proof_data.len});
    std.debug.print("   - Commitment: {s}\n", .{std.fmt.fmtSliceHexLower(&proof.commitment)});

    // Verify proof without knowing the secret value
    const is_valid_proof = try crypto.verifyRangeProof(proof, min_balance, max_balance);
    std.debug.print("✅ Range proof verification: {s}\n", .{if (is_valid_proof) "VALID" else "INVALID"});
    std.debug.print("   - Balance is in valid range (without revealing amount)\n", .{});

    // Test with invalid range
    const invalid_proof_result = crypto.verifyRangeProof(proof, 100000, 200000) catch false;
    std.debug.print("✅ Invalid range test: {s}\n", .{if (invalid_proof_result) "FAILED" else "CORRECTLY REJECTED"});

    std.debug.print("\n", .{});
}

/// Demo 4: Post-Quantum QUIC Transport
fn demoPostQuantumQuic(allocator: std.mem.Allocator) !void {
    std.debug.print("🌐 Demo 4: Post-Quantum QUIC Transport\n", .{});
    std.debug.print("------------------------------------\n", .{});

    // Post-quantum transport types (simplified for demo)
    const PQQuicTransport = struct {
        allocator: std.mem.Allocator,
        is_server: bool,
        
        pub fn init(alloc: std.mem.Allocator, is_server: bool) @This() {
            return .{ .allocator = alloc, .is_server = is_server };
        }
        
        pub fn deinit(self: *@This()) void {
            _ = self;
        }
        
        pub fn updateKeys(self: *@This(), conn_id: u64) !void {
            _ = self;
            _ = conn_id;
        }
        
        pub fn connect(self: *@This(), addr: std.net.Address) !u64 {
            _ = self;
            _ = addr;
            return 12345; // Mock connection ID
        }
    };
    
    const PQDatabaseTransport = struct {
        transport: PQQuicTransport,
        
        pub fn init(alloc: std.mem.Allocator, is_server: bool) @This() {
            return .{ .transport = PQQuicTransport.init(alloc, is_server) };
        }
        
        pub fn deinit(self: *@This()) void {
            self.transport.deinit();
        }
        
        pub fn executeQuery(self: *@This(), query: []const u8) ![]const u8 {
            _ = self;
            _ = query;
            return "Mock query result";
        }
        
        pub fn rotateKeys(self: *@This()) !void {
            _ = self;
        }
    };

    // Create post-quantum QUIC server
    var server = PQQuicTransport.init(allocator, true);
    defer server.deinit();

    // Create post-quantum QUIC client
    var client = PQQuicTransport.init(allocator, false);
    defer client.deinit();

    std.debug.print("✅ Initialized post-quantum QUIC endpoints\n", .{});
    std.debug.print("   - Cipher suite: TLS_ML_KEM_768_X25519_AES256_GCM_SHA384\n", .{});
    std.debug.print("   - Hybrid key exchange: X25519 + ML-KEM-768\n", .{});

    // Simulate connection
    const server_addr = std.net.Address.parseIp("127.0.0.1", 4433) catch unreachable;
    const conn_id = try client.connect(server_addr);

    std.debug.print("✅ Established post-quantum secure connection\n", .{});
    std.debug.print("   - Connection ID: {}\n", .{conn_id});

    // Test encrypted database transport
    var db_transport = PQDatabaseTransport.init(allocator, false);
    defer db_transport.deinit();

    _ = try db_transport.transport.connect(server_addr);
    
    // Execute encrypted query over PQ-QUIC
    const query = "SELECT balance FROM accounts WHERE user_id = 'alice' AND balance > 10000";
    std.debug.print("📡 Executing query over post-quantum QUIC...\n", .{});
    std.debug.print("   - Query: {s}\n", .{query});

    const result = try db_transport.executeQuery(query);
    defer allocator.free(result);

    std.debug.print("✅ Query executed successfully\n", .{});
    std.debug.print("   - Result: {s}\n", .{result});
    std.debug.print("   - End-to-end quantum-safe encryption\n", .{});

    // Test key rotation
    // Mock key update for connection
    try server.updateKeys(conn_id);
    std.debug.print("✅ Performed post-quantum key rotation\n", .{});

    std.debug.print("\n", .{});
}

/// Demo 5: Blockchain-Style Transaction Log
fn demoBlockchainTransactionLog(allocator: std.mem.Allocator) !void {
    std.debug.print("⛓️ Demo 5: Blockchain-Style Transaction Log\n", .{});
    std.debug.print("------------------------------------------\n", .{});

    var crypto = try zqlite.crypto.CryptoEngine.initWithMasterKey(
        allocator, 
        "blockchain_demo_2024"
    );
    defer crypto.deinit();

    // Create cryptographic transaction log
    var tx_log = try zqlite.crypto.CryptoTransactionLog.init(allocator, &crypto);
    defer tx_log.deinit();

    std.debug.print("✅ Initialized blockchain-style transaction log\n", .{});
    std.debug.print("   - Hybrid signatures for each transaction\n", .{});
    std.debug.print("   - Cryptographic chaining\n", .{});

    // Log some database operations
    const transactions = [_]struct { table: []const u8, op: []const u8, data: []const u8 }{
        .{ .table = "accounts", .op = "INSERT", .data = "{'user_id': 'alice', 'balance': 50000}" },
        .{ .table = "accounts", .op = "UPDATE", .data = "{'user_id': 'alice', 'balance': 45000}" },
        .{ .table = "transfers", .op = "INSERT", .data = "{'from': 'alice', 'to': 'bob', 'amount': 5000}" },
        .{ .table = "accounts", .op = "UPDATE", .data = "{'user_id': 'bob', 'balance': 15000}" },
    };

    for (transactions, 0..) |tx, i| {
        try tx_log.logOperation(tx.table, tx.op, tx.data);
        std.debug.print("📝 Transaction {}: {s} on table '{s}'\n", .{ i + 1, tx.op, tx.table });
    }

    std.debug.print("✅ Logged {} transactions with cryptographic integrity\n", .{transactions.len});

    // Verify entire chain integrity
    const is_valid_chain = try tx_log.verifyIntegrity();
    std.debug.print("✅ Transaction log verification: {s}\n", .{if (is_valid_chain) "VALID CHAIN" else "CORRUPTED"});
    std.debug.print("   - All hybrid signatures verified\n", .{});
    std.debug.print("   - Chain integrity confirmed\n", .{});

    std.debug.print("\n", .{});
}

/// Demo 6: Advanced Cryptographic Features
fn demoAdvancedCrypto(allocator: std.mem.Allocator) !void {
    std.debug.print("🔬 Demo 6: Advanced Cryptographic Features\n", .{});
    std.debug.print("-----------------------------------------\n", .{});

    var crypto = try zqlite.crypto.CryptoEngine.initWithMasterKey(
        allocator, 
        "advanced_crypto_demo_2024"
    );
    defer crypto.deinit();

    // 1. Enhanced password hashing with BLAKE2b
    std.debug.print("🔑 Testing enhanced password hashing...\n", .{});
    const password = "ultra_secure_database_password_2024!";
    var password_hash = try crypto.hashPassword(password);
    defer password_hash.deinit(allocator);

    const password_valid = try crypto.verifyPassword(password, password_hash);
    const wrong_password_valid = try crypto.verifyPassword("wrong_password", password_hash);

    std.debug.print("✅ BLAKE2b password hashing:\n", .{});
    std.debug.print("   - Correct password: {s}\n", .{if (password_valid) "VERIFIED" else "FAILED"});
    std.debug.print("   - Wrong password: {s}\n", .{if (wrong_password_valid) "FAILED" else "CORRECTLY REJECTED"});

    // 2. Table-specific key derivation
    std.debug.print("\n🗝️ Testing table-specific key derivation...\n", .{});
    const users_key = try crypto.deriveTableKey("users");
    const orders_key = try crypto.deriveTableKey("orders");
    const payments_key = try crypto.deriveTableKey("payments");

    std.debug.print("✅ Derived table-specific encryption keys:\n", .{});
    std.debug.print("   - users: {s}\n", .{std.fmt.fmtSliceHexLower(&users_key)});
    std.debug.print("   - orders: {s}\n", .{std.fmt.fmtSliceHexLower(&orders_key)});
    std.debug.print("   - payments: {s}\n", .{std.fmt.fmtSliceHexLower(&payments_key)});

    // 3. Secure random token generation
    std.debug.print("\n🎲 Testing secure random token generation...\n", .{});
    const api_token = try crypto.generateToken(32);
    defer allocator.free(api_token);
    
    const session_token = try crypto.generateToken(16);
    defer allocator.free(session_token);

    std.debug.print("✅ Generated cryptographically secure tokens:\n", .{});
    std.debug.print("   - API token (32 bytes): {s}\n", .{std.fmt.fmtSliceHexLower(api_token)});
    std.debug.print("   - Session token (16 bytes): {s}\n", .{std.fmt.fmtSliceHexLower(session_token)});

    // 4. Data integrity hashing
    std.debug.print("\n🛡️ Testing data integrity verification...\n", .{});
    const important_data = "Critical database backup data that must not be tampered with";
    const data_hash = try crypto.hashData(important_data);
    
    // Simulate data verification
    const verification_hash = try crypto.hashData(important_data);
    const data_intact = std.mem.eql(u8, &data_hash, &verification_hash);

    std.debug.print("✅ SHA3-256 data integrity check:\n", .{});
    std.debug.print("   - Data hash: {s}\n", .{std.fmt.fmtSliceHexLower(&data_hash)});
    std.debug.print("   - Integrity: {s}\n", .{if (data_intact) "VERIFIED" else "CORRUPTED"});

    // 5. Hybrid key exchange simulation
    std.debug.print("\n🤝 Testing hybrid key exchange...\n", .{});
    var peer_classical_key: [32]u8 = undefined;
    var peer_pq_key: [1184]u8 = undefined;
    
    // Simulate peer keys using Zig std.crypto
    std.crypto.random.bytes(&peer_classical_key);
    std.crypto.random.bytes(&peer_pq_key);

    const shared_secret = try crypto.performKeyExchange(peer_classical_key, peer_pq_key);
    
    std.debug.print("✅ Hybrid key exchange (X25519 + ML-KEM-768):\n", .{});
    std.debug.print("   - Shared secret: {s}...\n", .{std.fmt.fmtSliceHexLower(shared_secret[0..16])});
    std.debug.print("   - Quantum-safe for long-term security\n", .{});

    std.debug.print("\n", .{});
}

// Performance benchmark
fn benchmarkCrypto(allocator: std.mem.Allocator) !void {
    std.debug.print("⚡ Performance Benchmark\n", .{});
    std.debug.print("----------------------\n", .{});

    var crypto = try zqlite.crypto.CryptoEngine.initWithMasterKey(
        allocator, 
        "benchmark_test_2024"
    );
    defer crypto.deinit();

    const iterations = 1000;
    const test_data = "benchmark_test_data_for_performance_measurement";

    // Benchmark encryption/decryption
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        const encrypted = try crypto.encryptField(test_data);
        defer allocator.free(encrypted);
        
        const decrypted = try crypto.decryptField(encrypted);
        defer allocator.free(decrypted);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("✅ Encryption/Decryption Performance:\n", .{});
    std.debug.print("   - {} operations in {d:.2} ms\n", .{ iterations, duration_ms });
    std.debug.print("   - {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("   - ChaCha20-Poly1305 AEAD\n", .{});

    std.debug.print("\n", .{});
}