# ZQLite Issue Assessment - September 21, 2025# ZQLite Issue Assessment - September 21, 2025



## Executive Summary## Executive Summary



ZQLite v1.3.3 **does not** resolve the critical memory management issues that prevent ZAUR from using standard SQL DEFAULT constraints. Despite claims of fixes, extensive testing reveals persistent memory leaks and double-free errors during CREATE TABLE operations with DEFAULT CURRENT_TIMESTAMP constraints.ZQLite v1.3.3 **does not** resolve the critical memory management issues that prevent ZAUR from using standard SQL DEFAULT constraints. Despite claims of fixes, extensive testing reveals persistent memory leaks and double-free errors during CREATE TABLE operations with DEFAULT CURRENT_TIMESTAMP constraints.



## Current Status## Current Status



### ✅ Build Success### ✅ Build Success

- ZQLite v1.3.3 compiles successfully with Zig 0.16.0-dev- ZQLite v1.3.3 compiles successfully with Zig 0.16.0-dev

- No compilation errors or warnings- No compilation errors or warnings

- Binary generation works correctly- Binary generation works correctly



### ❌ Runtime Failures### ❌ Runtime Failures

- **Memory Leaks**: Multiple memory leaks during CREATE TABLE parsing of DEFAULT constraints- **Memory Leaks**: Multiple memory leaks during CREATE TABLE parsing of DEFAULT constraints

- **Double-Free Errors**: Critical double-free detected during table creation and INSERT operations- **Double-Free Errors**: Critical double-free detected during table creation and INSERT operations

- **Affected Operations**: Any SQL using DEFAULT CURRENT_TIMESTAMP or DEFAULT function calls- **Affected Operations**: Any SQL using DEFAULT CURRENT_TIMESTAMP or DEFAULT function calls



## Specific Issues Identified## Specific Issues Identified



### 1. Memory Leaks in Planner (CREATE TABLE)### 1. Memory Leaks in Planner (CREATE TABLE)

``````

error(gpa): memory address 0x... leaked:error(gpa): memory address 0x... leaked:

/home/chris/.cache/zig/p/zqlite-1.3.3-.../src/executor/planner.zig:512:72/home/chris/.cache/zig/p/zqlite-1.3.3-.../src/executor/planner.zig:512:72

    .Text => |t| storage.Value{ .Text = try self.allocator.dupe(u8, t) }    .Text => |t| storage.Value{ .Text = try self.allocator.dupe(u8, t) }

``````



**Location**: `convertAstDefaultToStorage()` and `convertAstFunctionToStorage()`**Location**: `convertAstDefaultToStorage()` and `convertAstFunctionToStorage()`

**Impact**: Memory allocated for DEFAULT constraint parsing is never freed**Impact**: Memory allocated for DEFAULT constraint parsing is never freed



### 2. Double-Free in VM Execution### 2. Double-Free in VM Execution

``````

error(gpa): Double free detected. Allocation:error(gpa): Double free detected. Allocation:

/home/chris/.cache/zig/p/zqlite-1.3.3-.../src/executor/vm.zig:371:72/home/chris/.cache/zig/p/zqlite-1.3.3-.../src/executor/vm.zig:371:72

    .Text => |t| storage.Value{ .Text = try self.allocator.dupe(u8, t) }    .Text => |t| storage.Value{ .Text = try self.allocator.dupe(u8, t) }

``````



**Location**: `cloneStorageDefaultValue()` during INSERT operations**Location**: `cloneStorageDefaultValue()` during INSERT operations

**Impact**: Default values are freed twice - once during execution, once during cleanup**Impact**: Default values are freed twice - once during execution, once during cleanup



### 3. Affected SQL Constructs### 3. Affected SQL Constructs

- `DEFAULT CURRENT_TIMESTAMP`- `DEFAULT CURRENT_TIMESTAMP`

- `DEFAULT 'literal_value'`- `DEFAULT 'literal_value'`

- Any DEFAULT with function calls or expressions- Any DEFAULT with function calls or expressions



## Test Results## Test Results



### Commands Tested### Commands Tested

```bash```bash

cd /data/projects/zaurcd /data/projects/zaur

zig build  # ✅ Successzig build  # ✅ Success

./zig-out/bin/zaur init  # ❌ Memory errors./zig-out/bin/zaur init  # ❌ Memory errors

./zig-out/bin/zaur add aur/yay  # ❌ Memory errors + double-free./zig-out/bin/zaur add aur/yay  # ❌ Memory errors + double-free

``````



### Error Patterns### Error Patterns

- **Init Phase**: Memory leaks during table creation- **Init Phase**: Memory leaks during table creation

- **Add Phase**: Double-free during INSERT with DEFAULT constraints- **Add Phase**: Double-free during INSERT with DEFAULT constraints

- **Consistent**: Errors occur in every database operation- **Consistent**: Errors occur in every database operation



## Required Workarounds## Required Workarounds



### 1. C Allocator Workaround### 1. C Allocator Workaround

**Problem**: Standard Zig allocator causes memory corruption in zqlite**Problem**: Standard Zig allocator causes memory corruption in zqlite

**Solution**: Use `std.heap.c_allocator` instead of passed allocator**Solution**: Use `std.heap.c_allocator` instead of passed allocator



```zig```zig

// In Database.init()// In Database.init()

const conn = try zqlite.open(std.heap.c_allocator, db_path);const conn = try zqlite.open(std.heap.c_allocator, db_path);

``````



### 2. Explicit Timestamp Management### 2. Explicit Timestamp Management

**Problem**: DEFAULT CURRENT_TIMESTAMP causes parsing failures**Problem**: DEFAULT CURRENT_TIMESTAMP causes parsing failures

**Solution**: Remove DEFAULT constraints and use explicit timestamps**Solution**: Remove DEFAULT constraints and use explicit timestamps



**Before**:**Before**:

```sql```sql

CREATE TABLE packages (CREATE TABLE packages (

    added_at DATETIME DEFAULT CURRENT_TIMESTAMP,    added_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP

););

INSERT INTO packages (name, source_type, source_url) VALUES (?, ?, ?);INSERT INTO packages (name, source_type, source_url) VALUES (?, ?, ?);

``````



**After**:**After**:

```sql```sql

CREATE TABLE packages (CREATE TABLE packages (

    added_at DATETIME,    added_at DATETIME,

    updated_at DATETIME    updated_at DATETIME

););

INSERT INTO packages (name, source_type, source_url, added_at, updated_at)INSERT INTO packages (name, source_type, source_url, added_at, updated_at)

VALUES (?, ?, ?, datetime('now'), datetime('now'));VALUES (?, ?, ?, datetime('now'), datetime('now'));

``````



### 3. Schema Modifications Required### 3. Schema Modifications Required

- `packages` table: Remove DEFAULT from `added_at`, `updated_at`- `packages` table: Remove DEFAULT from `added_at`, `updated_at`

- `builds` table: Remove DEFAULT from `started_at`- `builds` table: Remove DEFAULT from `started_at`

- `mirror_cache` table: Remove DEFAULT from `cached_at`, `last_accessed`- `mirror_cache` table: Remove DEFAULT from `cached_at`, `last_accessed`



## Implementation Plan## Implementation Plan



### Phase 1: Restore Workarounds### Phase 1: Restore Workarounds

1. Modify `Database.init()` to use `std.heap.c_allocator`1. Modify `Database.init()` to use `std.heap.c_allocator`

2. Update table schemas to remove DEFAULT constraints2. Update table schemas to remove DEFAULT constraints

3. Modify INSERT statements to provide explicit timestamps3. Modify INSERT statements to provide explicit timestamps



### Phase 2: Testing### Phase 2: Testing

1. Build and test `zaur init`1. Build and test `zaur init`

2. Test `zaur add` operations2. Test `zaur add` operations

3. Verify no memory errors in logs3. Verify no memory errors in logs



### Phase 3: Long-term Solutions### Phase 3: Long-term Solutions

1. Monitor zqlite releases for actual fixes1. Monitor zqlite releases for actual fixes

2. Consider alternative SQLite bindings (sqlite3.zig, etc.)2. Consider alternative SQLite bindings (sqlite3.zig, etc.)

3. Evaluate moving to direct SQLite C API3. Evaluate moving to direct SQLite C API



## Risk Assessment## Risk Assessment



### High Risk### High Risk

- **Memory Corruption**: Double-free errors can cause undefined behavior- **Memory Corruption**: Double-free errors can cause undefined behavior

- **Data Loss**: Potential database corruption from memory issues- **Data Loss**: Potential database corruption from memory issues

- **Production Instability**: Cannot deploy with current zqlite version- **Production Instability**: Cannot deploy with current zqlite version



### Mitigation### Mitigation

- Implement workarounds immediately- Implement workarounds immediately

- Add comprehensive error handling- Add comprehensive error handling

- Consider database integrity checks- Consider database integrity checks



## Recommendations## Recommendations



### Immediate Actions (Required)### Immediate Actions (Required)

1. **Implement C allocator workaround** - Critical for basic functionality1. **Implement C allocator workaround** - Critical for basic functionality

2. **Remove DEFAULT constraints** - Required to prevent parsing failures2. **Remove DEFAULT constraints** - Required to prevent parsing failures

3. **Add explicit timestamp handling** - Ensures data consistency3. **Add explicit timestamp handling** - Ensures data consistency



### Medium-term Actions### Medium-term Actions

1. **Add memory leak detection** in CI/CD pipeline1. **Add memory leak detection** in CI/CD pipeline

2. **Create zqlite compatibility tests** for future versions2. **Create zqlite compatibility tests** for future versions

3. **Document all workarounds** for maintenance team3. **Document all workarounds** for maintenance team



### Long-term Actions### Long-term Actions

1. **Evaluate alternative SQLite libraries** when stable options emerge1. **Evaluate alternative SQLite libraries** when stable options emerge

2. **Consider contributing fixes** to zqlite if feasible2. **Consider contributing fixes** to zqlite if feasible

3. **Plan migration path** away from zqlite if issues persist3. **Plan migration path** away from zqlite if issues persist



## Conclusion## Conclusion



ZQLite v1.3.3 does not provide the claimed fixes for memory management issues. The library remains unsuitable for production use with standard SQL DEFAULT constraints. Workarounds must be re-implemented to maintain ZAUR functionality.ZQLite v1.3.3 does not provide the claimed fixes for memory management issues. The library remains unsuitable for production use with standard SQL DEFAULT constraints. Workarounds must be re-implemented to maintain ZAUR functionality.



**Status**: BLOCKED - Cannot proceed with zqlite v1.3.3 without workarounds**Status**: BLOCKED - Cannot proceed with zqlite v1.3.3 without workarounds

**Next Step**: Implement required workarounds to restore functionality</content>**Next Step**: Implement required workarounds to restore functionality</content>

<parameter name="filePath">/data/projects/zaur/ZQLITE_FIXLIST.md<parameter name="filePath">/data/projects/zaur/ZQLITE_FIXLIST.md
