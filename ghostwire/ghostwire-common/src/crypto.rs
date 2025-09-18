//! Cryptographic utilities for Ghostwire

use ring::rand::{SecureRandom, SystemRandom};
use std::convert::TryInto;

/// Generate a new WireGuard private key
pub fn generate_private_key() -> [u8; 32] {
    let rng = SystemRandom::new();
    let mut key = [0u8; 32];
    rng.fill(&mut key).expect("Failed to generate random key");
    key
}

/// Generate the corresponding public key from a private key
pub fn generate_public_key(private_key: &[u8; 32]) -> [u8; 32] {
    // This is a placeholder - in a real implementation, you'd use curve25519-dalek
    // or similar to perform the scalar multiplication
    let mut public_key = [0u8; 32];

    // Simple placeholder transformation (NOT cryptographically secure)
    for (i, &byte) in private_key.iter().enumerate() {
        public_key[i] = byte.wrapping_add(9);
    }

    public_key
}

/// Generate a key pair (private, public)
pub fn generate_keypair() -> ([u8; 32], [u8; 32]) {
    let private_key = generate_private_key();
    let public_key = generate_public_key(&private_key);
    (private_key, public_key)
}

/// Encode key as base64
pub fn encode_key(key: &[u8; 32]) -> String {
    base64::encode(key)
}

/// Decode key from base64
pub fn decode_key(encoded: &str) -> Result<[u8; 32], base64::DecodeError> {
    let bytes = base64::decode(encoded)?;
    if bytes.len() != 32 {
        return Err(base64::DecodeError::InvalidLength);
    }

    Ok(bytes.try_into().unwrap())
}