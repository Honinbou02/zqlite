# NEXTGEN ZQLITE - Enhancement Roadmap

## Overview
This document outlines the necessary improvements and additions to zqlite (Pure Zig SQLite Clone) based on real-world usage in the ZAUR project.

## Critical SQL Parser Improvements

### 1. SQL Comments Support
**Priority: HIGH**
- Add support for inline comments: `-- comment`
- Add support for multi-line comments: `/* comment */`
- Essential for readable schema definitions

### 2. Extended Data Types
**Priority: HIGH**
- `DATETIME` - Map to TEXT internally but recognize the type
- `TIMESTAMP` - Same as DATETIME
- `BOOLEAN` - Map to INTEGER (0/1)
- `REAL` / `FLOAT` / `DOUBLE` - Floating point support
- `BLOB` - Binary data support

### 3. DEFAULT Value Functions
**Priority: HIGH**
- `CURRENT_TIMESTAMP` - Auto-set current time
- `CURRENT_DATE` - Auto-set current date
- `CURRENT_TIME` - Auto-set current time
- `datetime('now')` - SQLite-style datetime function
- Custom default functions

### 4. Table Constraints
**Priority: MEDIUM**
- `FOREIGN KEY` constraints with `REFERENCES`
- `CHECK` constraints
- `UNIQUE` constraints on multiple columns
- Composite `PRIMARY KEY`
- `ON DELETE CASCADE/SET NULL/RESTRICT`
- `ON UPDATE CASCADE/SET NULL/RESTRICT`

### 5. Advanced CREATE TABLE Features
**Priority: MEDIUM**
- `IF NOT EXISTS` clause ✅ (already supported)
- `AUTOINCREMENT` for INTEGER PRIMARY KEY
- `WITHOUT ROWID` tables
- `TEMPORARY` tables
- Column collations (`COLLATE NOCASE`, etc.)

## Query Enhancements

### 6. JOIN Operations
**Priority: HIGH**
- `INNER JOIN`
- `LEFT JOIN` / `LEFT OUTER JOIN`
- `RIGHT JOIN` / `RIGHT OUTER JOIN`
- `FULL OUTER JOIN`
- `CROSS JOIN`
- Multiple JOIN conditions

### 7. Aggregate Functions
**Priority: HIGH**
- `COUNT()` with DISTINCT
- `SUM()`, `AVG()`, `MIN()`, `MAX()`
- `GROUP_CONCAT()`
- `GROUP BY` clause
- `HAVING` clause

### 8. Window Functions
**Priority: LOW**
- `ROW_NUMBER()`, `RANK()`, `DENSE_RANK()`
- `LEAD()`, `LAG()`
- `OVER` clause with partitioning

### 9. Subqueries
**Priority: MEDIUM**
- Subqueries in SELECT
- Subqueries in FROM (derived tables)
- Subqueries in WHERE (`IN`, `EXISTS`, `ANY`, `ALL`)
- Correlated subqueries

## Data Manipulation

### 10. UPDATE Enhancements
**Priority: HIGH**
- `UPDATE ... SET ... FROM` syntax
- Multiple column updates
- Conditional updates with CASE
- Update with JOIN

### 11. INSERT Enhancements
**Priority: HIGH**
- `INSERT OR REPLACE` ✅ (needs testing)
- `INSERT OR IGNORE`
- `INSERT ... ON CONFLICT`
- `INSERT ... SELECT`
- Multi-row inserts
- `RETURNING` clause

### 12. DELETE Enhancements
**Priority: MEDIUM**
- `DELETE FROM ... USING`
- `DELETE ... RETURNING`
- Delete with JOIN

## Function Support

### 13. String Functions
**Priority: MEDIUM**
- `LENGTH()`, `SUBSTR()`, `REPLACE()`
- `UPPER()`, `LOWER()`, `TRIM()`
- `LTRIM()`, `RTRIM()`
- `INSTR()`, `LIKE` pattern matching
- `GLOB` pattern matching

### 14. Date/Time Functions
**Priority: HIGH**
- `date()`, `time()`, `datetime()`
- `strftime()` for formatting
- `julianday()`
- Date arithmetic

### 15. Math Functions
**Priority: LOW**
- `ABS()`, `ROUND()`, `CEIL()`, `FLOOR()`
- `POWER()`, `SQRT()`
- `RANDOM()`

## Transaction Support

### 16. Transaction Control
**Priority: HIGH**
- `BEGIN TRANSACTION`
- `COMMIT`
- `ROLLBACK`
- `SAVEPOINT` and nested transactions
- Transaction isolation levels

## Index Management

### 17. Index Operations
**Priority: MEDIUM**
- `CREATE INDEX`
- `CREATE UNIQUE INDEX`
- `DROP INDEX`
- Partial indexes
- Expression indexes
- Multi-column indexes

## View Support

### 18. Views
**Priority: LOW**
- `CREATE VIEW`
- `DROP VIEW`
- Updatable views
- Materialized views (future)

## Performance Features

### 19. Query Optimization
**Priority: MEDIUM**
- Query plan analyzer
- Statistics gathering
- Cost-based optimizer
- Index usage hints

### 20. Caching
**Priority: MEDIUM**
- Prepared statement caching
- Result set caching
- Schema caching

## Compatibility Features

### 21. SQLite Compatibility Mode
**Priority: HIGH**
- Full SQLite3 SQL dialect support
- Compatible error codes
- Compatible type affinity rules
- PRAGMA statements

### 22. Migration Tools
**Priority: MEDIUM**
- Import from SQLite databases
- Export to SQLite format
- Schema migration support

## API Improvements

### 23. Connection Pool
**Priority: MEDIUM**
- Connection pooling for concurrent access
- Connection lifecycle management
- Automatic reconnection

### 24. Async/Await Support
**Priority: LOW**
- Async query execution
- Non-blocking I/O

### 25. Better Error Messages
**Priority: HIGH**
- Detailed parse error messages with position
- Suggestion for common mistakes
- Stack traces for debugging

## Testing & Documentation

### 26. Comprehensive Test Suite
**Priority: HIGH**
- SQL compliance tests
- Performance benchmarks
- Stress tests
- Compatibility tests with SQLite

### 27. Documentation
**Priority: HIGH**
- Complete SQL dialect documentation
- API reference
- Migration guide from SQLite
- Performance tuning guide

## Implementation Priority

### Phase 1 (Immediate - Required for ZAUR)
1. SQL Comments support
2. Extended data types (DATETIME, TIMESTAMP)
3. DEFAULT value functions (CURRENT_TIMESTAMP)
4. FOREIGN KEY constraints
5. Better error messages

### Phase 2 (Short-term)
1. JOIN operations
2. Aggregate functions
3. Transaction support
4. String and Date functions
5. UPDATE/INSERT enhancements

### Phase 3 (Medium-term)
1. Index management
2. Subqueries
3. Query optimization
4. Connection pooling
5. SQLite compatibility mode

### Phase 4 (Long-term)
1. Window functions
2. Views
3. Async support
4. Advanced performance features

## Compatibility Notes

The goal is to make zqlite a drop-in replacement for SQLite in Zig projects, with:
- Full SQL-92 compliance
- SQLite-specific extensions
- Pure Zig implementation (no C dependencies)
- Better performance for Zig-specific use cases

## Contributing

When implementing these features:
1. Maintain backward compatibility
2. Follow Zig best practices
3. Include comprehensive tests
4. Update documentation
5. Consider performance implications

## Current Workarounds (Used in ZAUR)

Until these features are implemented, we use these workarounds:
- Remove SQL comments from queries
- Use TEXT instead of DATETIME
- Remove DEFAULT CURRENT_TIMESTAMP
- Remove FOREIGN KEY constraints
- Simplify UNIQUE constraints
- Handle timestamps in application code