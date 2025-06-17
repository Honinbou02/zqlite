const std = @import("std");
const encryption = @import("encryption.zig");

/// Page-based storage manager
pub const Pager = struct {
    allocator: std.mem.Allocator,
    file: ?std.fs.File,
    page_cache: std.AutoHashMap(u32, *Page),
    lru_list: std.ArrayList(u32), // LRU tracking
    next_page_id: u32,
    page_size: u32,
    is_memory: bool,
    cache_hits: u64,
    cache_misses: u64,
    encryption: encryption.Encryption,

    const Self = @This();
    const DEFAULT_PAGE_SIZE = 4096;
    const MAX_CACHED_PAGES = 1000;

    /// Initialize pager with file backing
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !*Self {
        var pager = try allocator.create(Self);
        pager.allocator = allocator;
        pager.page_cache = std.AutoHashMap(u32, *Page).init(allocator);
        pager.lru_list = std.ArrayList(u32).init(allocator);
        pager.page_size = DEFAULT_PAGE_SIZE;
        pager.is_memory = false;
        pager.next_page_id = 1;
        pager.cache_hits = 0;
        pager.cache_misses = 0;
        pager.encryption = encryption.Encryption.initPlain();

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
        pager.page_cache = std.AutoHashMap(u32, *Page).init(allocator);
        pager.lru_list = std.ArrayList(u32).init(allocator);
        pager.page_size = DEFAULT_PAGE_SIZE;
        pager.is_memory = true;
        pager.next_page_id = 1;
        pager.cache_hits = 0;
        pager.cache_misses = 0;
        pager.encryption = encryption.Encryption.initPlain();

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
            self.cache_hits += 1;
            try self.updateLRU(page_id);
            return page;
        }

        self.cache_misses += 1;

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
                if (bytes_read < self.page_size) { // Zero out remaining bytes if file is smaller
                    @memset(page.data[bytes_read..], 0);
                }
            }
        } else {
            // In-memory: page doesn't exist yet, zero it out
            @memset(page.data, 0);
        }

        // Add to cache
        try self.page_cache.put(page_id, page);
        try self.updateLRU(page_id);

        // Evict pages if cache is too large
        if (self.page_cache.count() > MAX_CACHED_PAGES) {
            try self.evictPages();
        }

        return page;
    }

    /// Update LRU list
    fn updateLRU(self: *Self, page_id: u32) !void {
        // Remove page_id if it exists in LRU list
        for (self.lru_list.items, 0..) |id, i| {
            if (id == page_id) {
                _ = self.lru_list.swapRemove(i);
                break;
            }
        }

        // Add to end (most recently used)
        try self.lru_list.append(page_id);
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

    /// Evict some pages from cache using LRU strategy
    fn evictPages(self: *Self) !void {
        // Evict least recently used pages until we're under the limit
        const target_size = (MAX_CACHED_PAGES * 3) / 4; // Evict down to 75% capacity

        while (self.page_cache.count() > target_size and self.lru_list.items.len > 0) {
            const lru_page_id = self.lru_list.orderedRemove(0); // Remove least recently used

            if (self.page_cache.fetchRemove(lru_page_id)) |entry| {
                const page = entry.value;

                // Write dirty page before evicting
                if (page.is_dirty) {
                    try self.writePage(page);
                }

                // Clean up page
                self.allocator.free(page.data);
                self.allocator.destroy(page);
            }
        }
    }

    /// Get cache statistics
    pub fn getCacheStats(self: *Self) CacheStats {
        return CacheStats{
            .hits = self.cache_hits,
            .misses = self.cache_misses,
            .hit_ratio = if (self.cache_hits + self.cache_misses > 0)
                @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(self.cache_hits + self.cache_misses))
            else
                0.0,
            .cached_pages = @intCast(self.page_cache.count()),
        };
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
        self.lru_list.deinit();

        // Close file
        if (self.file) |file| {
            file.close();
        }

        self.allocator.destroy(self);
    }
};

/// Cache statistics
pub const CacheStats = struct {
    hits: u64,
    misses: u64,
    hit_ratio: f64,
    cached_pages: u32,
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
