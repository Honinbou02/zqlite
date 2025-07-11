const std = @import("std");
const zqlite = @import("zqlite");

/// ZNS (Zcrypto Name System) Integration Demo for ZQLite v0.8.0
/// Demonstrates Ghostchain ENS compatibility with post-quantum security

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.log.info("=== ZQLite v0.8.0 ZNS Integration Demo ===", .{});
    
    // Initialize crypto config with Shroud backend
    const crypto_config = zqlite.crypto.CryptoConfig{
        .backend = .shroud,
        .enable_pq = true,
        .enable_zkp = true,
        .hybrid_mode = true,
    };
    
    // Create ZNS database
    var zns_db = zqlite.zns_adapter.ZNSDatabase.init(allocator, crypto_config) catch |err| blk: {
        std.log.warn("Shroud not available, using native crypto: {}", .{err});
        const fallback_config = zqlite.crypto.CryptoConfig{
            .backend = .native,
            .enable_pq = false,
            .enable_zkp = false,
            .hybrid_mode = false,
        };
        break :blk try zqlite.zns_adapter.ZNSDatabase.init(allocator, fallback_config);
    };
    defer zns_db.deinit();
    
    try demonstrateZNSOperations(&zns_db);
    try demonstrateGhostchainIntegration(&zns_db);
    try demonstratePostQuantumSecurity(&zns_db);
    
    std.log.info("✅ ZNS Integration Demo Complete!", .{});
}

fn demonstrateZNSOperations(zns_db: *zqlite.zns_adapter.ZNSDatabase) !void {
    std.log.info("\n--- ZNS Basic Operations ---", .{});
    
    const current_time = @as(u64, @intCast(std.time.timestamp()));
    
    // Create some test records
    const records = [_]zqlite.zns_adapter.ZNSAdapter.ZNSRecord{
        .{
            .domain = "example.ghost",
            .record_type = .A,
            .value = "192.168.1.100",
            .signature = null,
            .timestamp = current_time,
        },
        .{
            .domain = "example.ghost",
            .record_type = .GHOSTCHAIN_ADDR,
            .value = "ghost1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
            .signature = null,
            .timestamp = current_time,
        },
        .{
            .domain = "secure.ghost",
            .record_type = .GHOSTCHAIN_PUBKEY,
            .value = "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
            .signature = null,
            .timestamp = current_time,
        },
        .{
            .domain = "mail.ghost",
            .record_type = .MX,
            .value = "10 mail.ghost",
            .signature = null,
            .timestamp = current_time,
        },
    };
    
    // Store records
    for (records) |record| {
        try zns_db.storeRecord(record);
        std.log.info("📝 Stored {s} record for {s}: {s}", .{ 
            @tagName(record.record_type), 
            record.domain, 
            record.value 
        });
    }
    
    // Query records
    std.log.info("\n--- Querying Records ---", .{});
    
    if (zns_db.getRecord("example.ghost", .A)) |record| {
        std.log.info("🔍 A record for example.ghost: {s}", .{record.value});
    }
    
    if (zns_db.resolveGhostchainAddress("example.ghost")) |address| {
        std.log.info("👻 Ghostchain address for example.ghost: {s}", .{address});
    }
    
    if (zns_db.getRecord("secure.ghost", .GHOSTCHAIN_PUBKEY)) |record| {
        std.log.info("🔐 Public key for secure.ghost: {s}", .{record.value});
    }
}

fn demonstrateGhostchainIntegration(zns_db: *zqlite.zns_adapter.ZNSDatabase) !void {
    std.log.info("\n--- Ghostchain Integration ---", .{});
    
    // Generate a mock public key for demonstration
    const mock_pubkey = "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5";
    
    // Generate ZNS address from public key
    const zns_address = try zns_db.adapter.generateZNSAddress(mock_pubkey);
    
    std.log.info("🏷️  Generated ZNS Address:", .{});
    std.log.info("   Public Key: {s}", .{mock_pubkey});
    std.log.info("   ZNS Address: {s}", .{std.fmt.fmtSliceHexLower(&zns_address)});
    
    // Demonstrate domain hash generation
    const domain_hash = try zns_db.adapter.domainHash("example.ghost", .GHOSTCHAIN_ADDR);
    std.log.info("🏷️  Domain Hash for example.ghost: {s}", .{std.fmt.fmtSliceHexLower(&domain_hash)});
    
    // Test record validation
    const test_record = zqlite.zns_adapter.ZNSAdapter.ZNSRecord{
        .domain = "test.ghost",
        .record_type = .GHOSTCHAIN_ADDR,
        .value = "ghost1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
        .signature = null,
        .timestamp = @as(u64, @intCast(std.time.timestamp())),
    };
    
    const is_valid = try zns_db.adapter.validateRecord(test_record);
    std.log.info("✅ Record validation result: {}", .{is_valid});
}

fn demonstratePostQuantumSecurity(zns_db: *zqlite.zns_adapter.ZNSDatabase) !void {
    std.log.info("\n--- Post-Quantum Security Features ---", .{});
    
    // Check if post-quantum crypto is available
    const has_pq = zns_db.adapter.crypto.hasPQCrypto();
    const has_zkp = zns_db.adapter.crypto.hasZKP();
    
    std.log.info("🔬 Post-Quantum Crypto Available: {}", .{has_pq});
    std.log.info("🔬 Zero-Knowledge Proofs Available: {}", .{has_zkp});
    
    if (has_pq) {
        std.log.info("🛡️  Post-quantum features:", .{});
        std.log.info("   - ML-KEM-768 key encapsulation", .{});
        std.log.info("   - ML-DSA-65 digital signatures", .{});
        std.log.info("   - Hybrid classical+PQ security", .{});
    } else {
        std.log.info("📝 Using classical crypto fallback", .{});
        std.log.info("   - Ed25519 signatures", .{});
        std.log.info("   - X25519 key exchange", .{});
        std.log.info("   - ChaCha20-Poly1305 encryption", .{});
    }
    
    // Demonstrate data encryption/decryption
    const test_data = "Sensitive ZNS configuration data";
    const test_domain = "secure.ghost";
    
    std.log.info("\n--- Data Encryption Demo ---", .{});
    std.log.info("📄 Original data: {s}", .{test_data});
    
    const encrypted = try zns_db.adapter.encryptZNSData(test_data, test_domain);
    std.log.info("🔒 Encrypted data ({} bytes)", .{encrypted.ciphertext.len});
    std.log.info("   Nonce: {s}", .{std.fmt.fmtSliceHexLower(&encrypted.nonce)});
    std.log.info("   Tag: {s}", .{std.fmt.fmtSliceHexLower(&encrypted.tag)});
    
    const decrypted = try zns_db.adapter.decryptZNSData(encrypted, test_domain);
    defer zns_db.adapter.allocator.free(decrypted);
    defer zns_db.adapter.allocator.free(encrypted.ciphertext);
    
    std.log.info("🔓 Decrypted data: {s}", .{decrypted});
    std.log.info("✅ Encryption/Decryption successful: {}", .{std.mem.eql(u8, test_data, decrypted)});
}

fn demonstrateHashVerification() !void {
    std.log.info("\n--- Hash Verification Demo ---", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create hash verifier with default ZQLite hashes
    var verifier = try zqlite.crypto.HashVerifier.initWithDefaults(allocator, .{});
    defer verifier.deinit();
    
    // Test dependency verification
    const tokioz_hash = "TokioZ-0.0.0-DgtPReljAgAuGaoLtQCm_E-UA_7j_TAGQ8kkV-mtjz4V";
    const shroud_hash = "1220216b86fd00b71421251224cf53f7f0185c2375d94c758302e43de8db5a5815e3";
    
    std.log.info("🔍 Verifying TokioZ hash: {}", .{verifier.verifyDependencyHash("tokioz", tokioz_hash)});
    std.log.info("🔍 Verifying Shroud hash: {}", .{verifier.verifyDependencyHash("shroud", shroud_hash)});
    
    // Test with invalid hash
    std.log.info("❌ Testing invalid hash: {}", .{verifier.verifyDependencyHash("tokioz", "invalid_hash")});
    
    // Create stability monitor
    var monitor = zqlite.crypto.StabilityMonitor.init(allocator, .{});
    defer monitor.deinit();
    
    // Simulate some operations
    try monitor.recordOperation("hash_calculation");
    try monitor.recordOperation("hash_calculation");
    try monitor.recordOperation("encryption");
    try monitor.recordError("hash_calculation"); // One error
    
    std.log.info("📊 Hash calculation error rate: {d:.2}%", .{monitor.getErrorRate("hash_calculation") * 100.0});
    std.log.info("📊 System stable: {}", .{monitor.isStable()});
    
    const report = try monitor.generateReport();
    defer allocator.free(report);
    std.log.info("📊 Stability Report:\n{s}", .{report});
}

// Test runner for all demos
test "zns_integration_demo" {
    try main();
    try demonstrateHashVerification();
}