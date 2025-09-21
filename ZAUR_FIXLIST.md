# ZQLite Production Readiness Issues

## Overview
ZQLite v1.3.2 claims to be production-ready but still has critical issues that prevent reliable database operations. While some new features work (like `datetime('now')` in examples), core functionality remains broken.

## Critical Issues

### 1. Memory Leaks in CREATE TABLE Operations
**Status:** ❌ Still Broken in v1.3.2
**Impact:** High - Prevents production use with GPA allocator
**Error:** `error(gpa): memory address 0x... leaked`
**Location:** `convertAstDefaultToStorage`, `cloneStorageDefaultValue`, `executeCreateTable`

**Workaround:** Use `std.heap.c_allocator` instead of GPA
```zig
// Instead of:
const conn = try zqlite.open(allocator, db_path);
// Use:
const conn = try zqlite.open(std.heap.c_allocator, db_path);
```

### 2. DEFAULT Constraint Evaluation Failure
**Status:** ❌ Still Broken in v1.3.2
**Impact:** Critical - Basic INSERT operations fail
**Error:** `MissingRequiredValue` during INSERT execution
**Root Cause:** DEFAULT values not applied when columns omitted from INSERT

**Workaround:** Explicitly specify all columns in INSERT statements
```zig
// Instead of relying on DEFAULT:
INSERT INTO packages (name, source_type, source_url) VALUES (?, ?, ?);

// Must specify all columns:
INSERT OR REPLACE INTO packages (name, version, source_type, source_url, build_status, added_at, updated_at)
VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'));
```

### 3. Function Call Parsing in INSERT VALUES
**Status:** ❌ Still Broken in v1.3.2
**Impact:** Medium - Cannot use expressions in INSERT
**Error:** `ExpectedValue` when parsing `datetime('now')` in INSERT VALUES

**Workaround:** Use function calls in table schema DEFAULT clauses only
```zig
// Works in CREATE TABLE:
added_at TEXT DEFAULT (datetime('now'))

// Doesn't work in INSERT VALUES:
INSERT INTO table (col) VALUES (datetime('now')) // ❌ Fails
```

### 4. CURRENT_TIMESTAMP Support
**Status:** ❌ Still Broken in v1.3.2
**Impact:** Medium - Standard SQL timestamp syntax not supported
**Error:** Parser rejects `CURRENT_TIMESTAMP` keyword

**Workaround:** Use `datetime('now')` instead
```zig
// Instead of:
added_at DATETIME DEFAULT CURRENT_TIMESTAMP

// Use:
added_at TEXT DEFAULT (datetime('now'))
```

## Partially Working Features

### ✅ What Works in v1.3.2
- Basic table creation with `datetime('now')` DEFAULT clauses
- Simple INSERT operations when all columns specified
- Basic SELECT queries
- Connection management
- Some datetime functions in queries

### ✅ Examples That Work
- `simple_api_test.zig` - Basic operations
- `datetime_test.zig` - DEFAULT datetime functions
- `insert_memory_regression_test.zig` - Basic INSERT patterns

## Required Fixes for Production Readiness

### High Priority
1. **Fix Memory Leaks**: Complete cleanup in all DEFAULT value processing paths
2. **Implement DEFAULT Evaluation**: Apply DEFAULT constraints during INSERT when columns omitted
3. **Fix Function Parsing**: Allow function calls in INSERT VALUES clauses

### Medium Priority
4. **Add CURRENT_TIMESTAMP Support**: Parse and handle standard SQL timestamp syntax
5. **Improve Error Messages**: More descriptive parsing errors instead of generic "ExpectedValue"
6. **Complete Function Support**: Full SQLite function compatibility

### Low Priority
7. **Performance Optimization**: Reduce memory allocations in hot paths
8. **API Consistency**: Standardize parameter binding and result handling

## Current Workarounds Summary

```zig
// Database initialization
pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !Database {
    // Must use C allocator to avoid leaks
    const conn = try zqlite.open(std.heap.c_allocator, db_path);
    // ... rest of init
}

// Table schema
const create_packages_sql =
    \\CREATE TABLE IF NOT EXISTS packages (
    \\    id INTEGER PRIMARY KEY,
    \\    name TEXT NOT NULL UNIQUE,
    \\    version TEXT DEFAULT 'unknown',
    \\    source_type TEXT NOT NULL,
    \\    source_url TEXT NOT NULL,
    \\    build_status TEXT DEFAULT 'pending',
    \\    added_at TEXT DEFAULT (datetime('now')),     // Use datetime('now') not CURRENT_TIMESTAMP
    \\    updated_at TEXT DEFAULT (datetime('now'))
    \\);

// INSERT operations
pub fn addPackage(self: *Database, name: []const u8, source_type: []const u8, source_url: []const u8) !void {
    // Must specify ALL columns explicitly
    const sql =
        \\INSERT OR REPLACE INTO packages (name, version, source_type, source_url, build_status, added_at, updated_at)
        \\VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'));
    // ... binding and execution
}
```

## Testing Status

- **Memory Tests:** ❌ Fail with GPA allocator
- **INSERT Tests:** ❌ Fail when relying on DEFAULT constraints
- **Basic Operations:** ✅ Work with explicit workarounds
- **Datetime Functions:** ✅ Work in CREATE TABLE DEFAULT clauses

## Recommendation

ZQLite v1.3.2 is **not production-ready** for applications requiring:
- Standard SQL DEFAULT constraint behavior
- Memory leak-free operation with Zig's GPA
- CURRENT_TIMESTAMP syntax support
- Function calls in INSERT VALUES

**Use only with explicit workarounds** or wait for v1.3.3 with proper fixes.</content>
<parameter name="filePath">/data/projects/zaur/ZQLITE_FIXLIST.md
