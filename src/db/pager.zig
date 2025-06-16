const std = @import("std");

/// Page-based storage manager
pub const Pager = struct {
    allocator: std.mem.Allocator,
    file: ?std.fs.File,
    page_cache: std.HashMap(u32, *Page, std.hash_map.DefaultContext(u32), std.hash_map.default_max_load_percentage),
    next_page_id: u32,
    page_size: u32,
    is_memory: bool,

    const Self = @This();
    const DEFAULT_PAGE_SIZE = 4096;
    const MAX_CACHED_PAGES = 1000;

    /// Initialize pager with file backing
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !*Self {
        var pager = try allocator.create(Self);
        pager.allocator = allocator;
        pager.page_cache = std.HashMap(u32, *Page, std.hash_map.DefaultContext(u32), std.hash_map.default_max_load_percentage).init(allocator);
        pager.page_size = DEFAULT_PAGE_SIZE;
        pager.is_memory = false;
        pager.next_page_id = 1;

        // Open or create the database file
        pager.file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = false }) catch |err| switch (err) {
            error.FileNotFound => try std.fs.cwd().createFile(path, .{ .read = true }),
            else => return err,
        };

        // Read existing page count from file if it exists
        if (pager.file) |file| {
            const file_size = try file.getEndPos();
            if (file_size > 0) {
                pager.next_page_id = @intCast((file_size / DEFAULT_PAGE_SIZE) + 1);
            }
        }

        return pager;
    }

    /// Initialize in-memory pager
    pub fn initMemory(allocator: std.mem.Allocator) !*Self {
        var pager = try allocator.create(Self);
        pager.allocator = allocator;
        pager.file = null;
        pager.page_cache = std.HashMap(u32, *Page, std.hash_map.DefaultContext(u32), std.hash_map.default_max_load_percentage).init(allocator);
        pager.page_size = DEFAULT_PAGE_SIZE;
        pager.is_memory = true;
        pager.next_page_id = 1;

        return pager;
    }

    /// Allocate a new page
    pub fn allocatePage(self: *Self) !u32 {
        const page_id = self.next_page_id;
        self.next_page_id += 1;

        // Create new page
        const page = try self.allocator.create(Page);
        page.* = Page{
            .id = page_id,
            .data = try self.allocator.alloc(u8, self.page_size),
            .is_dirty = true,
        };

        // Zero out the page
        @memset(page.data, 0);

        // Add to cache
        try self.page_cache.put(page_id, page);

        return page_id;
    }

    /// Get a page (from cache or storage)
    pub fn getPage(self: *Self, page_id: u32) !*Page {
        // Check cache first
        if (self.page_cache.get(page_id)) |page| {
            return page;
        }

        // Load from storage
        const page = try self.allocator.create(Page);
        page.* = Page{
            .id = page_id,
            .data = try self.allocator.alloc(u8, self.page_size),
            .is_dirty = false,
        };

        if (!self.is_memory) {
            if (self.file) |file| {
                const offset = (page_id - 1) * self.page_size;
                _ = try file.seekTo(offset);

                const bytes_read = try file.read(page.data);
                if (bytes_read < self.page_size) {
                    // Zero out remaining bytes if file is smaller
                    @memset(page.data[bytes_read..], 0);
                }
            }
        } else {
            // In-memory: page doesn't exist yet, zero it out
            @memset(page.data, 0);
        }

        // Add to cache
        try self.page_cache.put(page_id, page);

        // Evict pages if cache is too large
        if (self.page_cache.count() > MAX_CACHED_PAGES) {
            try self.evictPages();
        }

        return page;
    }

    /// Mark a page as dirty (needs to be written to storage)
    pub fn markDirty(self: *Self, page_id: u32) !void {
        if (self.page_cache.get(page_id)) |page| {
            page.is_dirty = true;
        } else {
            return error.PageNotInCache;
        }
    }

    /// Flush all dirty pages to storage
    pub fn flush(self: *Self) !void {
        if (self.is_memory) return; // No flushing needed for in-memory

        var iterator = self.page_cache.iterator();
        while (iterator.next()) |entry| {
            const page = entry.value_ptr.*;
            if (page.is_dirty) {
                try self.writePage(page);
                page.is_dirty = false;
            }
        }

        // Sync file to disk
        if (self.file) |file| {
            try file.sync();
        }
    }

    /// Write a page to storage
    fn writePage(self: *Self, page: *Page) !void {
        if (self.file) |file| {
            const offset = (page.id - 1) * self.page_size;
            _ = try file.seekTo(offset);
            _ = try file.writeAll(page.data);
        }
    }

    /// Evict some pages from cache
    fn evictPages(self: *Self) !void {
        // Simple eviction: remove first 10% of pages
        const to_evict = self.page_cache.count() / 10;
        var evicted: u32 = 0;

        var iterator = self.page_cache.iterator();
        var pages_to_remove = std.ArrayList(u32).init(self.allocator);
        defer pages_to_remove.deinit();

        while (iterator.next()) |entry| {
            if (evicted >= to_evict) break;

            const page = entry.value_ptr.*;
            if (page.is_dirty) {
                try self.writePage(page);
            }

            try pages_to_remove.append(entry.key_ptr.*);
            evicted += 1;
        }

        // Remove from cache
        for (pages_to_remove.items) |page_id| {
            if (self.page_cache.fetchRemove(page_id)) |entry| {
                self.allocator.free(entry.value.data);
                self.allocator.destroy(entry.value);
            }
        }
    }

    /// Get total number of pages
    pub fn getPageCount(self: *Self) u32 {
        return self.next_page_id - 1;
    }

    /// Clean up pager
    pub fn deinit(self: *Self) void {
        // Flush any remaining dirty pages
        self.flush() catch {};

        // Clean up cache
        var iterator = self.page_cache.iterator();
        while (iterator.next()) |entry| {
            const page = entry.value_ptr.*;
            self.allocator.free(page.data);
            self.allocator.destroy(page);
        }
        self.page_cache.deinit();

        // Close file
        if (self.file) |file| {
            file.close();
        }

        self.allocator.destroy(self);
    }
};

/// Database page
pub const Page = struct {
    id: u32,
    data: []u8,
    is_dirty: bool,
};

test "pager creation" {
    const allocator = std.testing.allocator;
    const pager = try Pager.initMemory(allocator);
    defer pager.deinit();

    try std.testing.expect(pager.is_memory);
    try std.testing.expectEqual(@as(u32, 1), pager.next_page_id);
}

test "page allocation" {
    const allocator = std.testing.allocator;
    const pager = try Pager.initMemory(allocator);
    defer pager.deinit();

    const page_id = try pager.allocatePage();
    try std.testing.expectEqual(@as(u32, 1), page_id);
    try std.testing.expectEqual(@as(u32, 2), pager.next_page_id);
}
