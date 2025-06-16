# zqlite 
# zqlite 🟦

![Build](https://img.shields.io/github/actions/workflow/status/ghostkellz/zqlite/build.yml?style=flat-square)
![Zig](https://img.shields.io/badge/zig-0.15.0+-f7a41d?style=flat-square)
![Status](https://img.shields.io/badge/status-alpha-orange?style=flat-square)

> Lightweight, embedded, SQL-compatible database engine written in Zig. Inspired by SQLite, reimagined for the Zig era.

---

## 🧠 Overview

**`zqlite`** is a blazing-fast, standalone, embedded SQL-compatible database built from scratch in Zig.
It provides durable, transactional, and schema-based data storage with zero dependencies and a clean modular architecture.

Perfect for CLI tools, offline-first apps, embedded systems, or self-hosted services that want Zig-native data access.

---

## ✨ Features

* ✅ Lightweight B-tree-backed storage engine
* ✅ Zig-native API with zero FFI
* ✅ SQL parsing (SELECT, INSERT, CREATE TABLE, WHERE, etc.)
* ✅ Transaction support with WAL (Write-Ahead Logging)
* ✅ In-memory DB support (`:memory:`)
* ✅ Extensible modular architecture
* ✅ ACID compliance (Atomicity, Consistency, Isolation, Durability)
* ✅ Small static binary size (< 500KB)

---

## 🚀 Getting Started

### 1. Clone and Build

```bash
zig build run
```

Or integrate into your Zig project:

```zig
const zqlite = @import("zqlite");
var db = try zqlite.db.open("my.db");
db.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);");
```

### 2. Use From CLI (Planned)

```bash
$ ./zqlite
zqlite> SELECT * FROM users;
```

---

## 🔧 Planned SQL Support

| Feature           | Status                  |
| ----------------- | ----------------------- |
| `CREATE TABLE`    | ✅ Basic support         |
| `INSERT`          | ✅ Initial support       |
| `SELECT`          | ✅ With `WHERE`, `LIMIT` |
| `UPDATE`/`DELETE` | ⏳ Planned               |
| `JOIN`/`GROUP BY` | ⏳ Later versions        |

---

## 🗂️ Project Structure

```bash
zqlite/
├── db/          # Core engine: storage, WAL, pager
├── parser/      # SQL tokenizer, AST, parser
├── executor/    # Planner, VM, query execution
├── shell/       # CLI (optional)
├── tests/       # Unit tests for core modules
└── build.zig    # Build system
```

---

## 📚 Use Cases

* 🔧 Embedded config/state database
* 🐧 Self-hosted CLI tools (GhostCTL, ZAUR, PhantomBoot)
* 🔐 Secure offline-first apps
* ⚙️ Custom package metadata storage
* 🧪 Educational DB internals and compiler experiments

---

## 🛠️ Roadmap

* [ ] `UPDATE`, `DELETE`, `ALTER TABLE`
* [ ] CLI shell + REPL
* [ ] Secondary indexes
* [ ] Pluggable backends (in-memory, encrypted, etc.)
* [ ] Zig-native JSON column support
* [ ] FTS (Full-text search) module

---

## 🤝 Contributing

Want to help build the fastest Zig-native embedded database?

* Fork the repo
* `zig build test`
* Submit clean, well-commented PRs

---

## 📜 License

MIT License © 2025 [GhostKellz](https://github.com/ghostkellz)

---

## 🔗 Related Projects

* [SQLite](https://sqlite.org)
* [Zig](https://ziglang.org)
* [ZAUR](https://github.com/ghostkellz/zaur) – Zig Arch User Repo server
* [zmake](https://github.com/ghostkellz/zmake) – Zig package builder

