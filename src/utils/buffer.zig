const std = @import("std");
const errors = @import("../core/errors.zig");
const BufferError = errors.BufferError;

/// A high-performance circular buffer implementation
pub const CircularBuffer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffer: []u8,
    read_pos: usize,
    write_pos: usize,
    full: bool,
    mutex: std.Thread.Mutex,
    compaction_threshold: usize = 0.75,
    last_compaction: usize = 0,
    compaction_interval_ms: u32 = 5000,

    pub fn compact(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.isEmpty()) return;

        var temp_buffer = try self.allocator.alloc(u8, self.buffer.len);
        defer self.allocator.free(temp_buffer);

        var bytes_copied: usize = 0;
        while (bytes_copied < self.len()) {
            temp_buffer[bytes_copied] = self.buffer[self.read_pos];
            self.read_pos = (self.read_pos + 1) % self.buffer.len;
            bytes_copied += 1;
        }

        self.read_pos = 0;
        self.write_pos = bytes_copied;
        self.full = false;

        @memcpy(self.buffer[0..bytes_copied], temp_buffer[0..bytes_copied]);
        self.last_compaction = std.time.timestamp();
    }

    /// Initialize a new circular buffer with the specified size
    pub fn init(allocator: std.mem.Allocator, size: usize) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, size),
            .read_pos = 0,
            .write_pos = 0,
            .full = false,
            .mutex = std.Thread.Mutex{},
        };
        return self;
    }

    /// Free the buffer's memory
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
        self.allocator.destroy(self);
    }

    /// Write data to the buffer
    pub fn write(self: *Self, data: []const u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (data.len > self.capacity()) {
            return BufferError.BufferOverflow;
        }

        var bytes_written: usize = 0;
        for (data) |byte| {
            if (self.full) {
                return bytes_written;
            }

            self.buffer[self.write_pos] = byte;
            bytes_written += 1;
            self.write_pos = (self.write_pos + 1) % self.buffer.len;
            self.full = self.write_pos == self.read_pos;
        }

        const now = std.time.timestamp();
        const fragmentation: f64 = @floatFromInt(self.getFragmentedSpace() / self.buffer.len);

        if (fragmentation > self.compaction_threshold and now - self.last_compaction > self.compaction_interval_ms) {
            try self.compact();
        }
        return bytes_written;
    }

    // Helper to calculate fragmented space
    fn getFragmentedSpace(self: *Self) usize {
        if (self.isEmpty()) return 0;
        if (self.write_pos > self.read_pos) {
            return self.buffer.len - (self.write_pos - self.read_pos);
        }
        return self.read_pos - self.write_pos;
    }

    /// Read data from the buffer
    pub fn read(self: *Self, dest: []u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.isEmpty()) {
            return BufferError.BufferUnderflow;
        }

        var bytes_read: usize = 0;
        while (bytes_read < dest.len and !self.isEmpty()) {
            dest[bytes_read] = self.buffer[self.read_pos];
            bytes_read += 1;
            self.read_pos = (self.read_pos + 1) % self.buffer.len;
            self.full = false;
        }

        return bytes_read;
    }

    /// Get available space in the buffer
    pub fn capacity(self: *Self) usize {
        if (self.full) return 0;
        if (self.write_pos >= self.read_pos) {
            return self.buffer.len - (self.write_pos - self.read_pos);
        }
        return self.read_pos - self.write_pos;
    }

    /// Check if buffer is empty
    pub fn isEmpty(self: *Self) bool {
        return !self.full and self.read_pos == self.write_pos;
    }

    /// Reset buffer to initial state
    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.read_pos = 0;
        self.write_pos = 0;
        self.full = false;
    }

    /// Get the number of bytes stored in the buffer
    pub fn len(self: *Self) usize {
        if (self.full) return self.buffer.len;
        if (self.write_pos >= self.read_pos) {
            return self.write_pos - self.read_pos;
        }
        return self.buffer.len - (self.read_pos - self.write_pos);
    }
};

/// A buffer pool for managing multiple buffers
pub const BufferPool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffers: std.ArrayList(*CircularBuffer),
    buffer_size: usize,
    max_buffers: usize,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, buffer_size: usize, max_buffers: usize) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .buffers = std.ArrayList(*CircularBuffer).init(allocator),
            .buffer_size = buffer_size,
            .max_buffers = max_buffers,
            .mutex = std.Thread.Mutex{},
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.buffers.items) |buffer| {
            buffer.deinit();
        }
        self.buffers.deinit();
        self.allocator.destroy(self);
    }

    /// Get an available buffer or create a new one
    pub fn acquire(self: *Self) !*CircularBuffer {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Look for an empty buffer first
        for (self.buffers.items) |buffer| {
            if (buffer.isEmpty()) {
                return buffer;
            }
        }

        // Create a new buffer if under limit
        if (self.buffers.items.len < self.max_buffers) {
            const new_buffer = try CircularBuffer.init(self.allocator, self.buffer_size);
            try self.buffers.append(new_buffer);
            return new_buffer;
        }

        return BufferError.BufferFull;
    }

    /// Release a buffer back to the pool
    pub fn release(self: *Self, buffer: *CircularBuffer) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Verify the buffer belongs to this pool
        for (self.buffers.items) |pool_buffer| {
            if (pool_buffer == buffer) {
                buffer.reset();
                return;
            }
        }
        // If we get here, the buffer doesn't belong to this pool
        // In debug builds, we could assert or log this condition
        unreachable;
    }
};
