const std = @import("std");
const errors = @import("../core/errors.zig");

/// A generic object pool implementation
pub fn Pool(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Pool item wrapper to track status
        const PoolItem = struct {
            data: T,
            in_use: bool,
            last_used: i64,
            use_count: usize,
        };

        allocator: std.mem.Allocator,
        items: []PoolItem,
        create_fn: *const fn (allocator: std.mem.Allocator) errors.Error!T,
        destroy_fn: *const fn (item: *T) void,
        mutex: std.Thread.Mutex,
        stats: PoolStats,

        config: PoolConfig,

        pub const PoolConfig = struct {
            initial_size: usize,
            max_size: usize,
            growth_factor: f32 = 1.5,
            shrink_threshold: f32 = 0.5,
            item_timeout_ms: i64 = 60_000,
        };

        pub const PoolStats = struct {
            total_items: usize,
            items_in_use: usize,
            peak_usage: usize,
            total_acquisitions: usize,
            total_releases: usize,
        };

        /// Initialize a new pool
        pub fn init(
            allocator: std.mem.Allocator,
            config: PoolConfig,
            create_fn: *const fn (allocator: std.mem.Allocator) errors.Error!T,
            destroy_fn: *const fn (item: *T) void,
        ) !*Self {
            const self = try allocator.create(Self);

            self.* = .{
                .allocator = allocator,
                .items = try allocator.alloc(PoolItem, config.initial_size),
                .create_fn = create_fn,
                .destroy_fn = destroy_fn,
                .mutex = std.Thread.Mutex{},
                .stats = .{
                    .total_items = config.initial_size,
                    .items_in_use = 0,
                    .peak_usage = 0,
                    .total_acquisitions = 0,
                    .total_releases = 0,
                    .cache_hits = 0,
                    .cache_misses = 0,
                    .average_wait_time_ns = 0,
                },
                .config = config,
            };

            // Initialize pool items
            for (self.items) |*item| {
                item.* = .{
                    .data = try create_fn(allocator),
                    .in_use = false,
                    .last_used = 0,
                    .use_count = 0,
                };
            }

            return self;
        }

        /// Clean up pool resources
        pub fn deinit(self: *Self) void {
            for (self.items) |*item| {
                self.destroy_fn(&item.data);
            }
            self.allocator.free(self.items);
            self.allocator.destroy(self);
        }

        /// Acquire an item from the pool
        pub fn acquire(self: *Self) !*T {
            const start_time = std.time.nanoTimestamp();
            self.mutex.lock();
            defer self.mutex.unlock();

            // Try to find an available item
            const now = std.time.timestamp();
            for (self.items) |*item| {
                if (!item.in_use) {
                    item.in_use = true;
                    item.last_used = now;
                    item.use_count += 1;
                    self.stats.items_in_use += 1;
                    self.stats.total_acquisitions += 1;
                    self.stats.cache_hits += 1;
                    self.updateAverageWaitTime(start_time);
                    return &item.data;
                }
            }

            self.stats.cache_misses += 1;

            // Check if we can grow the pool
            if (self.items.len >= self.config.max_size) {
                // Try to reclaim timed-out items
                if (self.reclaimTimedOutItems(now)) |item| {
                    item.in_use = true;
                    item.last_used = now;
                    item.use_count += 1;
                    self.stats.items_in_use += 1;
                    self.stats.total_acquisitions += 1;
                    self.updateAverageWaitTime(start_time);
                    return &item.data;
                }
                return error.PoolExhausted;
            }
            // Grow pool
            const new_size = @min(self.config.max_size, @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.items.len)) * self.config.growth_factor)));
            try self.grow(new_size);

            // Use first new item
            const item = &self.items[self.items.len - 1];
            item.in_use = true;
            item.last_used = now;
            item.use_count = 1;
            self.stats.items_in_use += 1;
            self.stats.total_acquisitions += 1;
            self.updateAverageWaitTime(start_time);

            return &item.data;
        }

        fn reclaimTimedOutItems(self: *Self, now: i64) ?*PoolItem {
            for (self.items) |*item| {
                if (item.in_use and now - item.last_used > self.config.item_timeout_ms) {
                    item.in_use = false;
                    self.stats.items_in_use -= 1;
                    return item;
                }
            }
            return null;
        }

        // Update average wait time
        fn updateAverageWaitTime(self: *Self, start_time: i64) void {
            const wait_time: u64 = @intCast(std.time.nanoTimestamp() - start_time);
            const total_acquisitions = self.stats.total_acquisitions;
            self.stats.average_wait_time_ns = @divTrunc((self.stats.average_wait_time_ns * (total_acquisitions - 1) + wait_time), total_acquisitions);
        }

        /// Release an item back to the pool
        pub fn release(self: *Self, item: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            for (self.items) |*pool_item| {
                if (&pool_item.data == item) {
                    pool_item.in_use = false;
                    pool_item.last_used = std.time.timestamp();
                    self.stats.items_in_use -= 1;
                    self.stats.total_releases += 1;
                    // Check if we should shrink the pool
                    const usage_ratio: f32 = @as(f32, @floatFromInt(self.stats.items_in_use)) / @as(f32, @floatFromInt(self.items.len));
                    if (usage_ratio < self.config.shrink_threshold) {
                        self.shrinkToFit() catch {};
                    }
                    return;
                }
            }
        }

        /// Get current pool statistics
        pub fn getStats(self: *Self) PoolStats {
            return self.stats;
        }

        /// Shrink pool to fit current usage
        pub fn shrinkToFit(self: *Self) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            var active_count: usize = 0;
            for (self.items) |item| {
                if (item.in_use) active_count += 1;
            }

            // Add some padding to avoid frequent resizing
            const target_size = active_count + (active_count / 4);
            if (target_size >= self.items.len) return;

            var new_items = try self.allocator.alloc(PoolItem, target_size);
            var new_index: usize = 0;

            // Copy active items
            for (self.items) |item| {
                if (item.in_use) {
                    new_items[new_index] = item;
                    new_index += 1;
                } else {
                    self.destroy_fn(&item.data);
                }
            }

            // Update pool state
            self.allocator.free(self.items);
            self.items = new_items;
            self.stats.total_items = target_size;
        }
    };
}
