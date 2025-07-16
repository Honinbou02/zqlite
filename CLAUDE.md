# 🗃️ TODO: zqlite v1.2.0 – Refactor to Remove Shroud Dependency

> zqlite is a Zig-native embedded database and query engine.  
> v1.2.0 removes the legacy `shroud` dependency and ensures complete standalone operation with optional crypto/network hooks.

---

## 🎯 Core Goals

- [x] Fully remove all `shroud` dependencies
- [ ] Preserve all current database + query engine functionality
- [ ] Replace or stub identity/token logic previously handled by shroud
- [ ] Keep core dependency-free — no zcrypto or ghostnet unless explicitly enabled

---

## 🔍 Refactor Checklist

### 🔥 Remove from codebase
- [ ] All `@import("shroud")` references
- [ ] Any identity or access token logic via `shroud.access_token`
- [ ] All `shroud.guardian`-based role/permission checks
- [ ] Shroud-based DID or namespace resolution

### 🛠 Replace with stubs or built-ins
- [ ] Replace DIDs with raw `[]const u8` string identifiers
- [ ] Replace token-based access with pluggable policy callback (if needed)
- [ ] Replace `shroud.verify()` with `zcrypto` call or placeholder stub

---

## 🔐 Optional Interfaces (Future-Proofing)

Create optional, non-linked modules:

- `zqlite_crypto.zig` (optional):
  - `verify(data, sig, pubkey)`
  - `hash(data) → [32]u8`

- `zqlite_net.zig` (optional):
  - `fetchQuery(uri) → Query`
  - `resolveNamespace(ns) → []const u8`

These should only be imported via `comptime if (enable_crypto)` style toggles.

---

## 🧪 Tests

- [ ] Ensure all tests pass without any Shroud context
- [ ] Add regression test for query execution against in-memory tables
- [ ] Add negative test for removed identity logic

---

## 🧠 Guiding Principles

- 🧱 Deterministic
- 🧩 Embedded-first
- 🚫 No magic dependencies

---

## 📂 Suggested Structure


