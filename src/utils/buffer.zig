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

    compaction_threshold_percent: usize = 75,
    last_compaction: i64 = 0,
    compaction_interval_ms: i64 = 5000,

    total_bytes_written: std.atomic.Value(usize),
    total_compactions: std.atomic.Value(usize),

    pub fn compact(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.isEmpty()) return;

        const current_size = self.len();
        if (current_size == 0) return;

        // If data is contiguous, no need for temporary buffer
        if (self.read_pos < self.write_pos) return;

        // Only allocate temporary buffer if data wraps around
        var temp_buffer = try self.allocator.alloc(u8, current_size);
        defer self.allocator.free(temp_buffer);

        var bytes_copied: usize = 0;

        // Copy first segment (from read_pos to end)
        const first_segment = self.buffer[self.read_pos..];
        @memcpy(temp_buffer[0..first_segment.len], first_segment);
        bytes_copied += first_segment.len;

        // Copy second segment (from start to write_pos)
        if (self.write_pos > 0) {
            const second_segment = self.buffer[0..self.write_pos];
            @memcpy(temp_buffer[bytes_copied..], second_segment);
            bytes_copied += second_segment.len;
        }

        // Copy back to main buffer
        @memcpy(self.buffer[0..bytes_copied], temp_buffer[0..bytes_copied]);

        self.read_pos = 0;
        self.write_pos = bytes_copied;
        self.full = false;

        self.last_compaction = std.time.timestamp();
        _ = self.total_compactions.fetchAdd(1, .monotonic);
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
            .total_bytes_written = std.atomic.Value(usize).init(0),
            .total_compactions = std.atomic.Value(usize).init(0),
        };
        return self;
    }

    /// Free the buffer's memory
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
        self.allocator.destroy(self);
    }

    fn getFragmentationPercent(self: *Self) usize {
        const fragmented_space = self.getFragmentedSpace();
        return (fragmented_space * 100) / self.buffer.len;
    }

    /// Write data to the buffer
    pub fn write(self: *Self, data: []const u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Quick capacity check
        if (data.len > self.capacity()) {
            return BufferError.BufferOverflow;
        }

        // Check available space and perform compaction if needed
        const available_space = self.availableSpace();
        if (available_space < data.len) {
            // Try compaction first
            if (self.getFragmentationPercent() > self.compaction_threshold_percent) {
                try self.compact();
            }

            // If still not enough space after compaction
            if (self.availableSpace() < data.len) {
                return BufferError.BufferFull;
            }
        }

        var bytes_written: usize = 0;

        // Optimize for contiguous writes when possible
        if (self.write_pos + data.len <= self.buffer.len) {
            // Single copy for contiguous space
            @memcpy(self.buffer[self.write_pos..][0..data.len], data);
            bytes_written = data.len;
            self.write_pos = (self.write_pos + data.len) % self.buffer.len;
        } else {
            // Split copy for wrapped writes
            const first_chunk_size = self.buffer.len - self.write_pos;
            @memcpy(self.buffer[self.write_pos..], data[0..first_chunk_size]);
            @memcpy(self.buffer[0..], data[first_chunk_size..]);
            bytes_written = data.len;
            self.write_pos = data.len - first_chunk_size;
        }

        self.full = self.write_pos == self.read_pos;
        _ = self.total_bytes_written.fetchAdd(bytes_written, .monotonic);
        return bytes_written;
    }

    pub fn getStats(self: *Self) BufferStats {
        return .{
            .capacity = self.buffer.len,
            .used_space = self.len(),
            .total_bytes_written = self.total_bytes_written.load(.Acquire),
            .total_compactions = self.total_compactions.load(.Acquire),
            .fragmentation_percent = self.getFragmentationPercent(),
        };
    }

    fn compactInternal(self: *Self) !void {
        if (self.isEmpty()) return;

        var temp_buffer = try self.allocator.alloc(u8, self.buffer.len);
        defer self.allocator.free(temp_buffer);

        // Copy valid data to temporary buffer
        var bytes_copied: usize = 0;
        while (!self.isEmpty()) {
            const remaining = temp_buffer.len - bytes_copied;
            const bytes_read = try self.readInternal(temp_buffer[bytes_copied..remaining]);
            if (bytes_read == 0) break;
            bytes_copied += bytes_read;
        }

        // Reset buffer state
        self.read_pos = 0;
        self.write_pos = bytes_copied;
        self.full = bytes_copied == self.buffer.len;

        // Copy back to main buffer
        @memcpy(self.buffer[0..bytes_copied], temp_buffer[0..bytes_copied]);
        self.last_compaction = std.time.timestamp();
    }

    // Internal read function that assumes the lock is already held
    fn readInternal(self: *Self, dest: []u8) !usize {
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

    fn availableSpace(self: *Self) usize {
        if (self.full) return 0;
        if (self.write_pos >= self.read_pos) {
            return self.buffer.len - (self.write_pos - self.read_pos);
        }
        return self.read_pos - self.write_pos;
    }

    fn getFragmentedSpace(self: *Self) usize {
        if (self.full or self.isEmpty()) return 0;
        if (self.write_pos < self.read_pos) {
            return self.read_pos - self.write_pos;
        }
        return self.buffer.len - (self.write_pos - self.read_pos);
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

pub const BufferStats = struct {
    capacity: usize,
    used_space: usize,
    total_bytes_written: usize,
    total_compactions: usize,
    fragmentation_percent: usize,
};
