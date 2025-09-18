//! Row and result set handling for ZQLite

use crate::{zqlite_result_t, Error, Result};
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};

/// A set of rows returned from a query
pub struct Rows {
    inner: *mut zqlite_result_t,
    row_count: usize,
    column_count: usize,
    current_row: usize,
}

impl Rows {
    /// Create a new Rows from a ZQLite result pointer
    pub(crate) fn new(result_ptr: *mut zqlite_result_t) -> Self {
        let row_count = unsafe { crate::zqlite_result_row_count(result_ptr) as usize };
        let column_count = unsafe { crate::zqlite_result_column_count(result_ptr) as usize };

        Self {
            inner: result_ptr,
            row_count,
            column_count,
            current_row: 0,
        }
    }

    /// Get the number of rows in the result set
    pub fn row_count(&self) -> usize {
        self.row_count
    }

    /// Get the number of columns in the result set
    pub fn column_count(&self) -> usize {
        self.column_count
    }

    /// Get the column name at the specified index
    pub fn column_name(&self, column: usize) -> Result<String> {
        if column >= self.column_count {
            return Err(Error::index_out_of_bounds(column));
        }

        let name_ptr = unsafe { crate::zqlite_result_column_name(self.inner, column as c_int) };

        if name_ptr.is_null() {
            return Err(Error::NullPointer);
        }

        let name = unsafe { CStr::from_ptr(name_ptr).to_string_lossy().into_owned() };
        Ok(name)
    }

    /// Get all column names
    pub fn column_names(&self) -> Result<Vec<String>> {
        let mut names = Vec::with_capacity(self.column_count);
        for i in 0..self.column_count {
            names.push(self.column_name(i)?);
        }
        Ok(names)
    }
}

impl Iterator for Rows {
    type Item = Row;

    fn next(&mut self) -> Option<Self::Item> {
        if self.current_row >= self.row_count {
            return None;
        }

        let row = Row {
            result: self.inner,
            row_index: self.current_row,
            column_count: self.column_count,
        };

        self.current_row += 1;
        Some(row)
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        let remaining = self.row_count.saturating_sub(self.current_row);
        (remaining, Some(remaining))
    }
}

impl ExactSizeIterator for Rows {
    fn len(&self) -> usize {
        self.row_count.saturating_sub(self.current_row)
    }
}

impl Drop for Rows {
    fn drop(&mut self) {
        unsafe {
            crate::zqlite_result_free(self.inner);
        }
    }
}

/// A single row in a result set
pub struct Row {
    result: *mut zqlite_result_t,
    row_index: usize,
    column_count: usize,
}

impl Row {
    /// Get a value from the row by column index
    pub fn get<T: FromSql>(&self, column: usize) -> Result<T> {
        if column >= self.column_count {
            return Err(Error::index_out_of_bounds(column));
        }

        T::from_sql(self.result, self.row_index, column)
    }

    /// Get a value from the row by column name
    pub fn get_by_name<T: FromSql>(&self, column_name: &str) -> Result<T> {
        // Find column index by name
        for i in 0..self.column_count {
            let name_ptr = unsafe { crate::zqlite_result_column_name(self.result, i as c_int) };
            if !name_ptr.is_null() {
                let name = unsafe { CStr::from_ptr(name_ptr).to_string_lossy() };
                if name == column_name {
                    return self.get(i);
                }
            }
        }

        Err(Error::row_error(format!(
            "Column '{}' not found",
            column_name
        )))
    }

    /// Get the number of columns in this row
    pub fn column_count(&self) -> usize {
        self.column_count
    }

    /// Check if a column value is null
    pub fn is_null(&self, column: usize) -> Result<bool> {
        if column >= self.column_count {
            return Err(Error::index_out_of_bounds(column));
        }

        let column_type = unsafe {
            crate::zqlite_result_column_type(
                self.result,
                self.row_index as c_int,
                column as c_int,
            )
        };

        Ok(column_type == crate::ZQLITE_NULL as c_int)
    }
}

/// Trait for types that can be extracted from SQL result columns
pub trait FromSql: Sized {
    /// Extract a value from a SQL result
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self>;
}

impl FromSql for String {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let text_ptr = unsafe {
            crate::zqlite_result_get_text(result, row as c_int, column as c_int)
        };

        if text_ptr.is_null() {
            return Err(Error::NullPointer);
        }

        let text = unsafe { CStr::from_ptr(text_ptr).to_string_lossy().into_owned() };
        Ok(text)
    }
}

impl FromSql for Option<String> {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let column_type = unsafe {
            crate::zqlite_result_column_type(result, row as c_int, column as c_int)
        };

        if column_type == crate::ZQLITE_NULL as c_int {
            return Ok(None);
        }

        let text = String::from_sql(result, row, column)?;
        Ok(Some(text))
    }
}

impl FromSql for i64 {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let value = unsafe {
            crate::zqlite_result_get_int(result, row as c_int, column as c_int)
        };
        Ok(value)
    }
}

impl FromSql for Option<i64> {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let column_type = unsafe {
            crate::zqlite_result_column_type(result, row as c_int, column as c_int)
        };

        if column_type == crate::ZQLITE_NULL as c_int {
            return Ok(None);
        }

        let value = i64::from_sql(result, row, column)?;
        Ok(Some(value))
    }
}

impl FromSql for i32 {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let value = i64::from_sql(result, row, column)?;
        Ok(value as i32)
    }
}

impl FromSql for Option<i32> {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let value = Option::<i64>::from_sql(result, row, column)?;
        Ok(value.map(|v| v as i32))
    }
}

impl FromSql for f64 {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let value = unsafe {
            crate::zqlite_result_get_real(result, row as c_int, column as c_int)
        };
        Ok(value)
    }
}

impl FromSql for Option<f64> {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let column_type = unsafe {
            crate::zqlite_result_column_type(result, row as c_int, column as c_int)
        };

        if column_type == crate::ZQLITE_NULL as c_int {
            return Ok(None);
        }

        let value = f64::from_sql(result, row, column)?;
        Ok(Some(value))
    }
}

impl FromSql for bool {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let value = i64::from_sql(result, row, column)?;
        Ok(value != 0)
    }
}

impl FromSql for Option<bool> {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let value = Option::<i64>::from_sql(result, row, column)?;
        Ok(value.map(|v| v != 0))
    }
}

impl FromSql for Vec<u8> {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let mut size: c_int = 0;
        let blob_ptr = unsafe {
            crate::zqlite_result_get_blob(result, row as c_int, column as c_int, &mut size)
        };

        if blob_ptr.is_null() {
            return Err(Error::NullPointer);
        }

        let slice = unsafe { std::slice::from_raw_parts(blob_ptr as *const u8, size as usize) };
        Ok(slice.to_vec())
    }
}

impl FromSql for Option<Vec<u8>> {
    fn from_sql(result: *mut zqlite_result_t, row: usize, column: usize) -> Result<Self> {
        let column_type = unsafe {
            crate::zqlite_result_column_type(result, row as c_int, column as c_int)
        };

        if column_type == crate::ZQLITE_NULL as c_int {
            return Ok(None);
        }

        let blob = Vec::<u8>::from_sql(result, row, column)?;
        Ok(Some(blob))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Connection;

    #[test]
    fn test_row_extraction() {
        let conn = Connection::open(":memory:").unwrap();

        conn.execute(
            "CREATE TABLE test (
                id INTEGER,
                name TEXT,
                score REAL,
                active BOOLEAN,
                data BLOB
            )",
        )
        .unwrap();

        conn.execute(
            "INSERT INTO test VALUES (
                42,
                'test_user',
                95.5,
                1,
                X'48656C6C6F'
            )",
        )
        .unwrap();

        let rows = conn.query("SELECT * FROM test").unwrap();
        assert_eq!(rows.column_count(), 5);

        for row in rows {
            let id: i64 = row.get(0).unwrap();
            let name: String = row.get(1).unwrap();
            let score: f64 = row.get(2).unwrap();
            let active: bool = row.get(3).unwrap();
            let data: Vec<u8> = row.get(4).unwrap();

            assert_eq!(id, 42);
            assert_eq!(name, "test_user");
            assert!((score - 95.5).abs() < f64::EPSILON);
            assert!(active);
            assert_eq!(data, b"Hello");

            // Test by name access
            let name_by_name: String = row.get_by_name("name").unwrap();
            assert_eq!(name_by_name, "test_user");
        }
    }

    #[test]
    fn test_null_values() {
        let conn = Connection::open(":memory:").unwrap();

        conn.execute("CREATE TABLE test (id INTEGER, name TEXT)")
            .unwrap();
        conn.execute("INSERT INTO test VALUES (1, NULL)").unwrap();

        let rows = conn.query("SELECT * FROM test").unwrap();
        for row in rows {
            let id: i64 = row.get(0).unwrap();
            let name: Option<String> = row.get(1).unwrap();

            assert_eq!(id, 1);
            assert!(name.is_none());
            assert!(row.is_null(1).unwrap());
        }
    }
}