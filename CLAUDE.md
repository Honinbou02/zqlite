
## 🔧 zqlite Repository Fix Prompt

```
Hi! I need to fix a hash mismatch issue in my zqlite repository's build.zig.zon file. 

The error I'm getting when trying to use zqlite as a dependency in another project is:

```
error: hash mismatch: manifest declares '12202e7f593e522826cc2dc8da1d9f161f6e471d57f37dcae915a4f61e24211d89f4' but the fetched package has '1220a59a4d8c7bb7347cd2c1b4559bba4461dd9801dbf21c91f633d89f34e247b8d4'
```

I need you to:

1. **Check my current build.zig.zon file** - look for any hash mismatches in dependencies
2. **Fix any incorrect hashes** by running `zig fetch --save <url>` for each dependency 
3. **Verify the build.zig file** has the correct dependency imports
4. **Test that the project builds cleanly** with `zig build`
5. **Make sure the public API is stable** - especially the `zqlite.open()`, `db.execute()`, and `db.close()` functions

The main API I need working is:
```zig
const zqlite = @import("zqlite");

// Open database
const db = try zqlite.open("path/to/db.sqlite");

// Execute SQL
try db.execute("CREATE TABLE test (id INTEGER, name TEXT)");
try db.execute("INSERT INTO test VALUES (1, 'hello')");

// Close database  
db.close();
```

This is for integration with my Zepplin package registry project that needs persistent SQLite storage. The integration guide I'm following shows this exact API pattern working.

Can you check the current state of the repo and fix any dependency hash mismatches?
```

---

Once you fix the zqlite repository, you can come back here and:

1. **Uncomment the zqlite dependency** in build.zig.zon
2. **Run `zig fetch --save https://github.com/ghostkellz/zqlite/archive/main.tar.gz`** to get the correct hash
3. **Uncomment the zqlite import** in build.zig 
4. **Replace the database implementation** with the SQL version from ZQLITE_INTEGRATION.md

The LXC script is ready to go and will work great for production deployment! 🚀
