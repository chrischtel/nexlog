const std = @import("std");
const errors = @import("../core/errors.zig");
const BufferError = errors.BufferError;

/// A generic object pool implementation
pub fn Pool(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Pool item wrapper to track status
        const PoolItem = struct {
            data: T,
            in_use: bool,
        };

        allocator: std.mem.Allocator,
        items: []PoolItem,
        create_fn: *const fn (allocator: std.mem.Allocator) errors.Error!T,
        destroy_fn: *const fn (item: *T) void,
        mutex: std.Thread.Mutex,
        stats: PoolStats,

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
            initial_size: usize,
            create_fn: *const fn (allocator: std.mem.Allocator) errors.Error!T,
            destroy_fn: *const fn (item: *T) void,
        ) !*Self {
            const self = try allocator.create(Self);

            self.* = .{
                .allocator = allocator,
                .items = try allocator.alloc(PoolItem, initial_size),
                .create_fn = create_fn,
                .destroy_fn = destroy_fn,
                .mutex = std.Thread.Mutex{},
                .stats = .{
                    .total_items = initial_size,
                    .items_in_use = 0,
                    .peak_usage = 0,
                    .total_acquisitions = 0,
                    .total_releases = 0,
                },
            };

            // Initialize pool items
            for (self.items) |*item| {
                item.* = .{
                    .data = try create_fn(allocator),
                    .in_use = false,
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
            self.mutex.lock();
            defer self.mutex.unlock();

            // Find first available item
            for (self.items) |*item| {
                if (!item.in_use) {
                    item.in_use = true;
                    self.stats.items_in_use += 1;
                    self.stats.total_acquisitions += 1;
                    self.stats.peak_usage = @max(self.stats.peak_usage, self.stats.items_in_use);
                    return &item.data;
                }
            }

            // Grow pool if all items are in use
            const new_capacity = self.items.len * 2;
            var new_items = try self.allocator.alloc(PoolItem, new_capacity);

            // Copy existing items
            @memcpy(new_items[0..self.items.len], self.items);

            // Initialize new items
            for (new_items[self.items.len..]) |*item| {
                item.* = .{
                    .data = try self.create_fn(self.allocator),
                    .in_use = false,
                };
            }

            // Update pool state
            self.allocator.free(self.items);
            self.items = new_items;
            self.stats.total_items = new_capacity;

            // Use first new item
            const item = &self.items[self.items.len / 2];
            item.in_use = true;
            self.stats.items_in_use += 1;
            self.stats.total_acquisitions += 1;
            self.stats.peak_usage = @max(self.stats.peak_usage, self.stats.items_in_use);

            return &item.data;
        }

        /// Release an item back to the pool
        pub fn release(self: *Self, item: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Find and release the item
            for (self.items) |*pool_item| {
                if (&pool_item.data == item) {
                    pool_item.in_use = false;
                    self.stats.items_in_use -= 1;
                    self.stats.total_releases += 1;
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
