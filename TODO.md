# 🗃️ ZQLite v1.3.2 TODO - Memory Leak Fixes & Polish

> **Status**: v1.3.1 is production ready! 🎉
> All critical segfaults eliminated, ZAUR integration ready.
> This TODO covers remaining memory leaks and polish items.

---

## 🎯 **High Priority Memory Leaks**

### 🔍 **Parser Memory Leaks**
- [ ] **Fix parseSelect "*" leak** (`src/parser/parser.zig:68`)
  - Location: `try self.allocator.dupe(u8, "*")`
  - Issue: Duped "*" strings never freed in SELECT parsing
  - Impact: Memory leak on every SELECT query
  - Fix: Add proper cleanup in Statement.deinit()

### 🏭 **VM Execution Memory Leaks**
- [ ] **Fix executeCreateTable column name leaks** (`src/executor/vm.zig:432`)
  - Location: `try self.allocator.dupe(u8, column.name)`
  - Issue: Column names duped but never freed
  - Impact: Memory leak on every CREATE TABLE
  - Fix: Ensure Schema cleanup frees cloned column names

- [ ] **Fix cloneValue text duplication leaks** (`src/executor/vm.zig:324`)
  - Location: `storage.Value{ .Text = try self.allocator.dupe(u8, t) }`
  - Issue: Text values cloned in executeTableScan/evaluateExpression but not always freed
  - Impact: Memory leak on SELECT queries with text data
  - Fix: Ensure all cloned values are properly cleaned up in result deinit

### 🔄 **Expression Evaluation Leaks**
- [ ] **Fix evaluateExpression text cloning** (`src/executor/vm.zig:725`)
  - Location: Text value duplication in expression evaluation
  - Issue: Temporary values created during comparisons not freed
  - Impact: Memory leak on WHERE clauses with text comparisons
  - Fix: Add proper cleanup for temporary expression values

---

## 🧪 **Medium Priority Improvements**

### 📊 **Parser Enhancements**
- [ ] **Add support for COUNT(*) aggregate function**
  - Currently fails with "Expected identifier, found .{ .Count = void }"
  - Would enable more comprehensive SQL compliance testing
  - Location: Parser aggregate function handling

### 🔧 **API Consistency**
- [ ] **Update remaining demo files to use allocator parameter**
  - Several examples still need allocator API updates
  - Found during build: ghostwire_integration_demo, array_operations_demo, etc.
  - Fix: Update all `zqlite.openMemory()` calls to `zqlite.openMemory(allocator)`

### 🗂️ **Column Name Mapping**
- [ ] **Fix getValueByName() column mapping issues**
  - Currently column names don't match expected schema in SELECT results
  - Results show data in wrong column positions
  - Impact: getValueByName() returns wrong data (though doesn't crash)
  - Fix: Ensure column names are properly mapped in ResultSet creation

---

## 🏗️ **Low Priority Polish**

### 📝 **Documentation & Examples**
- [ ] **Clean up hardcoded version strings in comments**
  - Some files still have "ZQLite v1.2.2" in comments
  - Use centralized version info where appropriate

### 🧪 **Test Coverage**
- [ ] **Add comprehensive memory leak regression tests**
  - Create tests that specifically check for the fixed memory leaks
  - Use GPA in test mode to catch future leaks early

### 🔍 **Code Quality**
- [ ] **Review and optimize memory allocation patterns**
  - Look for opportunities to reduce unnecessary allocations
  - Consider object pooling for frequently allocated types

---

## 🚫 **Known Working - Do Not Touch**

> ⚠️ **CRITICAL**: These areas are now working correctly after fixes:

- ✅ getValueByName() segfault fix (Row ownership)
- ✅ "Invalid free" allocator mismatch fix
- ✅ INSERT operation memory management
- ✅ AUTOINCREMENT schema handling
- ✅ ExecutionResult cleanup in query operations
- ✅ API allocator parameter consistency

---

## 🎯 **Success Criteria for v1.3.2**

- [ ] **Zero memory leaks** in production readiness test
- [ ] **All examples build and run** without errors
- [ ] **COUNT(*) queries work** correctly
- [ ] **getValueByName() returns correct data** (not just avoid crashing)

---

## 💡 **Implementation Notes**

### Memory Leak Patterns Identified:
1. **Parser allocations** - Tend to allocate strings without proper cleanup paths
2. **VM cloneValue calls** - Create owned copies but cleanup responsibilities unclear
3. **Temporary expression values** - Created during evaluation but not tracked for cleanup

### Debugging Tips:
- Use `zig run test_production_ready.zig` to test fixes
- GPA allocator shows exact leak locations with stack traces
- Focus on `dupe()` calls - these are the main leak sources

### Architecture Notes:
- ResultSet now properly owns Row data (fixed in v1.3.1)
- ExecutionResult cleanup is working (fixed in v1.3.1)
- Connection allocator consistency established (fixed in v1.3.1)

---

**🎉 Great work on v1.3.1! ZQLite is now production ready for ZAUR.**
**Tomorrow's mission: Polish the memory management to perfection! 🚀**