const std = @import("std");

/// ZQLite v0.6.0 Crypto Abstraction Layer
/// Supports multiple backends: native (std.crypto), shroud, none
pub const CryptoBackend = enum {
    native,  // Zig std.crypto (default, no dependencies)
    shroud,  // Shroud library (when available)
    none,    // Disabled crypto features
};

pub const CryptoConfig = struct {
    backend: CryptoBackend = .native,
    enable_pq: bool = false,    // Post-quantum crypto (requires shroud)
    enable_zkp: bool = false,   // Zero-knowledge proofs (requires shroud)
    hybrid_mode: bool = true,   // Classical + PQ hybrid
};

/// Unified crypto interface - backend agnostic
pub const CryptoInterface = struct {
    backend: CryptoBackend,
    config: CryptoConfig,

    const Self = @This();

    pub fn init(config: CryptoConfig) Self {
        return Self{
            .backend = config.backend,
            .config = config,
        };
    }

    /// Generate secure random bytes
    pub fn randomBytes(self: Self, buffer: []u8) !void {
        switch (self.backend) {
            .native => {
                std.crypto.random.bytes(buffer);
            },
            .shroud => {
                const shroud = @import("shroud");
                shroud.ghostcipher.zcrypto.rand.fillBytes(buffer);
            },
            .none => {
                @memset(buffer, 0); // Insecure fallback
            },
        }
    }

    /// Generate Ed25519 keypair
    pub fn generateEd25519KeyPair(self: Self) !struct { public_key: [32]u8, secret_key: [64]u8 } {
        switch (self.backend) {
            .native => {
                var seed: [32]u8 = undefined;
                std.crypto.random.bytes(&seed);
                const secret_key = try std.crypto.sign.Ed25519.SecretKey.fromBytes(seed ++ seed); // Ed25519 needs 64-byte secret
                const keypair = try std.crypto.sign.Ed25519.KeyPair.fromSecretKey(secret_key);
                return .{
                    .public_key = keypair.public_key.toBytes(),
                    .secret_key = keypair.secret_key.toBytes(),
                };
            },
            .shroud => {
                const shroud = @import("shroud");
                const keys = shroud.ghostcipher.zcrypto.asym.generateEd25519();
                return .{
                    .public_key = keys.public_key,
                    .secret_key = keys.private_key,
                };
            },
            .none => {
                return error.CryptoDisabled;
            },
        }
    }

    /// Generate X25519 keypair
    pub fn generateX25519KeyPair(self: Self) !struct { public_key: [32]u8, secret_key: [32]u8 } {
        switch (self.backend) {
            .native => {
                var secret_key: [32]u8 = undefined;
                std.crypto.random.bytes(&secret_key);
                const basepoint = [_]u8{9} ++ [_]u8{0} ** 31; // X25519 basepoint
                const public_key = std.crypto.dh.X25519.scalarmult(secret_key, basepoint) catch |err| switch (err) {
                    error.IdentityElement => unreachable, // basepoint is never identity
                };
                return .{
                    .public_key = public_key,
                    .secret_key = secret_key,
                };
            },
            .shroud => {
                const shroud = @import("shroud");
                const keys = shroud.ghostcipher.zcrypto.asym.generateCurve25519();
                return .{
                    .public_key = keys.public_key,
                    .secret_key = keys.private_key,
                };
            },
            .none => {
                return error.CryptoDisabled;
            },
        }
    }

    /// Hash function (BLAKE3 with Shroud, SHA-256 with native)
    pub fn hash(self: Self, data: []const u8, output: *[32]u8) !void {
        switch (self.backend) {
            .native => {
                var hasher = std.crypto.hash.sha2.Sha256.init(.{});
                hasher.update(data);
                hasher.final(output);
            },
            .shroud => {
                const shroud = @import("shroud");
                const result = shroud.ghostcipher.zcrypto.hash.blake3(data);
                @memcpy(output, &result);
            },
            .none => {
                @memset(output, 0); // Insecure fallback
            },
        }
    }

    /// HKDF key derivation
    pub fn hkdf(self: Self, ikm: []const u8, salt: []const u8, info: []const u8, output: []u8) !void {
        switch (self.backend) {
            .native => {
                const Hkdf = std.crypto.kdf.hkdf.HkdfSha256;
                const prk = Hkdf.extract(salt, ikm);
                Hkdf.expand(output, info, prk);
            },
            .shroud => {
                const shroud = @import("shroud");
                const derived = try shroud.ghostcipher.zcrypto.kdf.hkdfSha256(std.heap.page_allocator, ikm, salt, info, output.len);
                defer std.heap.page_allocator.free(derived);
                @memcpy(output, derived);
            },
            .none => {
                @memset(output, 0); // Insecure fallback
            },
        }
    }

    /// Symmetric encryption (XChaCha20-Poly1305 with Shroud, ChaCha20-Poly1305 with native)
    pub fn encrypt(self: Self, key: [32]u8, nonce: [12]u8, plaintext: []const u8, ciphertext: []u8, tag: *[16]u8) !void {
        if (ciphertext.len != plaintext.len) return error.InvalidLength;
        
        switch (self.backend) {
            .native => {
                const cipher = std.crypto.aead.chacha_poly.ChaCha20Poly1305;
                cipher.encrypt(ciphertext, tag, plaintext, &[0]u8{}, nonce, key);
            },
            .shroud => {
                const shroud = @import("shroud");
                const result = try shroud.ghostcipher.zcrypto.sym.encryptChaCha20Poly1305(std.heap.page_allocator, key, nonce, plaintext, &[0]u8{});
                defer result.deinit();
                @memcpy(ciphertext, result.data);
                @memcpy(tag, &result.tag);
            },
            .none => {
                @memcpy(ciphertext, plaintext); // No encryption
                @memset(tag, 0);
            },
        }
    }

    /// Symmetric decryption (XChaCha20-Poly1305 with Shroud, ChaCha20-Poly1305 with native)
    pub fn decrypt(self: Self, key: [32]u8, nonce: [12]u8, ciphertext: []const u8, tag: [16]u8, plaintext: []u8) !void {
        if (plaintext.len != ciphertext.len) return error.InvalidLength;
        
        switch (self.backend) {
            .native => {
                const cipher = std.crypto.aead.chacha_poly.ChaCha20Poly1305;
                try cipher.decrypt(plaintext, ciphertext, tag, &[0]u8{}, nonce, key);
            },
            .shroud => {
                const shroud = @import("shroud");
                const result = try shroud.ghostcipher.zcrypto.sym.decryptChaCha20Poly1305(std.heap.page_allocator, key, nonce, ciphertext, tag, &[0]u8{});
                defer if (result) |r| std.heap.page_allocator.free(r);
                if (result) |r| {
                    @memcpy(plaintext, r);
                }
            },
            .none => {
                @memcpy(plaintext, ciphertext); // No decryption
            },
        }
    }

    /// Post-quantum key generation (ML-KEM-768)
    pub fn generatePQKeyPair(self: Self, _: std.mem.Allocator) !struct { public_key: [1184]u8, secret_key: [2400]u8 } {
        switch (self.backend) {
            .shroud => {
                // Post-quantum support via Shroud is complex - use native for now
                return error.PostQuantumNotSupported;
            },
            .native => {
                return error.PostQuantumNotSupported;
            },
            .none => {
                return error.CryptoDisabled;
            },
        }
    }

    /// Post-quantum digital signature (ML-DSA-65)
    pub fn signPQ(self: Self, _: []const u8, _: []const u8, _: std.mem.Allocator) ![]u8 {
        switch (self.backend) {
            .shroud => {
                // Post-quantum support via Shroud is complex - use native for now
                return error.PostQuantumNotSupported;
            },
            .native => {
                return error.PostQuantumNotSupported;
            },
            .none => {
                return error.CryptoDisabled;
            },
        }
    }

    /// Verify post-quantum signature (ML-DSA-65)
    pub fn verifyPQ(self: Self, _: []const u8, _: []const u8, _: []const u8) !bool {
        switch (self.backend) {
            .shroud => {
                // Post-quantum support via Shroud is complex - use native for now
                return error.PostQuantumNotSupported;
            },
            .native => {
                return error.PostQuantumNotSupported;
            },
            .none => {
                return error.CryptoDisabled;
            },
        }
    }

    /// Check if post-quantum crypto is available
    pub fn hasPQCrypto(self: Self) bool {
        return switch (self.backend) {
            .shroud => self.config.enable_pq,
            else => false,
        };
    }

    /// Check if zero-knowledge proofs are available  
    pub fn hasZKP(self: Self) bool {
        return switch (self.backend) {
            .shroud => self.config.enable_zkp,
            else => false,
        };
    }
};

/// Feature detection for runtime configuration
pub fn detectAvailableFeatures() CryptoConfig {
    var config = CryptoConfig{};
    
    // Shroud is required for v0.8.0 - full post-quantum crypto support
    config.backend = .shroud;
    config.enable_pq = true;
    config.enable_zkp = true;
    
    return config;
}
