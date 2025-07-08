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
                // TODO: Use Shroud when available
                return error.ShroudNotAvailable;
            },
            .none => {
                @memset(buffer, 0); // Insecure fallback
            },
        }
    }

    /// Hash function (SHA-256)
    pub fn hash(self: Self, data: []const u8, output: *[32]u8) !void {
        switch (self.backend) {
            .native => {
                var hasher = std.crypto.hash.sha2.Sha256.init(.{});
                hasher.update(data);
                hasher.final(output);
            },
            .shroud => {
                // TODO: Use Shroud when available
                return error.ShroudNotAvailable;
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
                // TODO: Use Shroud when available
                return error.ShroudNotAvailable;
            },
            .none => {
                @memset(output, 0); // Insecure fallback
            },
        }
    }

    /// Symmetric encryption (ChaCha20-Poly1305)
    pub fn encrypt(self: Self, key: [32]u8, nonce: [12]u8, plaintext: []const u8, ciphertext: []u8, tag: *[16]u8) !void {
        if (ciphertext.len != plaintext.len) return error.InvalidLength;
        
        switch (self.backend) {
            .native => {
                const cipher = std.crypto.aead.chacha_poly.ChaCha20Poly1305;
                cipher.encrypt(ciphertext, tag, plaintext, &[0]u8{}, nonce, key);
            },
            .shroud => {
                // TODO: Use Shroud when available
                return error.ShroudNotAvailable;
            },
            .none => {
                @memcpy(ciphertext, plaintext); // No encryption
                @memset(tag, 0);
            },
        }
    }

    /// Symmetric decryption (ChaCha20-Poly1305)
    pub fn decrypt(self: Self, key: [32]u8, nonce: [12]u8, ciphertext: []const u8, tag: [16]u8, plaintext: []u8) !void {
        if (plaintext.len != ciphertext.len) return error.InvalidLength;
        
        switch (self.backend) {
            .native => {
                const cipher = std.crypto.aead.chacha_poly.ChaCha20Poly1305;
                try cipher.decrypt(plaintext, ciphertext, tag, &[0]u8{}, nonce, key);
            },
            .shroud => {
                // TODO: Use Shroud when available
                return error.ShroudNotAvailable;
            },
            .none => {
                @memcpy(plaintext, ciphertext); // No decryption
            },
        }
    }

    /// Post-quantum key generation (ML-KEM-768)
    pub fn generatePQKeyPair(self: Self, allocator: std.mem.Allocator) !struct { public_key: [1184]u8, secret_key: [2400]u8 } {
        switch (self.backend) {
            .shroud => {
                if (@hasDecl(@import("root"), "shroud")) {
                    const shroud = @import("shroud");
                    return try shroud.ghostcipher.mlkem768.generateKeyPair(allocator);
                }
                return error.ShroudNotAvailable;
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
    pub fn signPQ(self: Self, message: []const u8, secret_key: []const u8, allocator: std.mem.Allocator) ![]u8 {
        switch (self.backend) {
            .shroud => {
                if (@hasDecl(@import("root"), "shroud")) {
                    const shroud = @import("shroud");
                    return try shroud.ghostcipher.mldsa65.sign(message, secret_key, allocator);
                }
                return error.ShroudNotAvailable;
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
    pub fn verifyPQ(self: Self, message: []const u8, signature: []const u8, public_key: []const u8) !bool {
        switch (self.backend) {
            .shroud => {
                if (@hasDecl(@import("root"), "shroud")) {
                    const shroud = @import("shroud");
                    return try shroud.ghostcipher.mldsa65.verify(message, signature, public_key);
                }
                return error.ShroudNotAvailable;
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
    
    // Check if Shroud is available at compile time
    if (@hasDecl(@import("root"), "shroud")) {
        config.backend = .shroud;
        config.enable_pq = true;
        config.enable_zkp = true;
    } else {
        config.backend = .native;
        config.enable_pq = false;
        config.enable_zkp = false;
    }
    
    return config;
}
