const std = @import("std");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");
const buffer = @import("../utils/buffer.zig");

pub const NetworkEndpoint = struct {
    host: []const u8,
    port: u16,
    secure: bool = false,
    path: []const u8 = "/logs",
};

pub const NetworkConfig = struct {
    endpoint: NetworkEndpoint,
    retry_attempts: u32 = 3,
    retry_delay_ms: u32 = 1000,
    buffer_size: usize = 32 * 1024, // 32KB default
    batch_size: usize = 100,
    flush_interval_ms: u32 = 5000,
    connect_timeout_ms: u32 = 5000,
};

pub const NetworkHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: NetworkConfig,
    mutex: std.Thread.Mutex,
    circular_buffer: *buffer.CircularBuffer,
    last_flush: i64,
    connection: ?std.net.Stream,
    reconnect_time: i64,
    batch_count: usize,

    pub fn init(allocator: std.mem.Allocator, config: NetworkConfig) !*Self {
        const self = try allocator.create(Self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .mutex = std.Thread.Mutex{},
            .circular_buffer = try buffer.CircularBuffer.init(allocator, config.buffer_size),
            .last_flush = std.time.timestamp(),
            .connection = null,
            .reconnect_time = 0,
            .batch_count = 0,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.connection) |conn| {
            conn.close();
        }
        self.circular_buffer.deinit();
        self.allocator.destroy(self);
    }

    pub fn write(self: *Self, level: types.LogLevel, message: []const u8, metadata: ?types.LogMetadata) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var fba = std.heap.FixedBufferAllocator.init(self.circular_buffer.buffer);
        const allocator = fba.allocator();

        // Format log entry as JSON
        const json_entry = try std.fmt.allocPrint(
            allocator,
            "{{\"timestamp\":{d},\"level\":\"{s}\",\"message\":\"{s}\"{s}}}\n",
            .{
                if (metadata) |m| m.timestamp else std.time.timestamp(),
                level.toString(),
                message,
                if (metadata) |m| try std.fmt.allocPrint(
                    allocator,
                    ",\"file\":\"{s}\",\"line\":{d},\"function\":\"{s}\"",
                    .{ m.file, m.line, m.function },
                ) else "",
            },
        );

        _ = try self.circular_buffer.write(json_entry);
        self.batch_count += 1;

        // Check if we need to flush
        if (self.shouldFlush()) {
            try self.flush();
        }
    }

    pub fn flush(self: *Self) !void {
        if (self.batch_count == 0) return;

        var retry_count: u32 = 0;
        while (retry_count < self.config.retry_attempts) : (retry_count += 1) {
            if (try self.ensureConnection()) |conn| {
                var temp_buffer: [4096]u8 = undefined;

                // Write batch header
                const header = try std.fmt.allocPrint(
                    self.allocator,
                    "POST {s} HTTP/1.1\r\nHost: {s}\r\nContent-Type: application/json\r\n\r\n",
                    .{ self.config.endpoint.path, self.config.endpoint.host },
                );
                defer self.allocator.free(header);

                try conn.writer().writeAll(header);

                // Send buffered logs
                while (true) {
                    const bytes_read = try self.circular_buffer.read(&temp_buffer);
                    if (bytes_read == 0) break;
                    try conn.writer().writeAll(temp_buffer[0..bytes_read]);
                }

                self.batch_count = 0;
                self.last_flush = std.time.timestamp();
                return;
            }

            // Wait before retry
            std.time.sleep(self.config.retry_delay_ms * std.time.ns_per_ms);
        }

        return error.NetworkError;
    }

    fn shouldFlush(self: *Self) bool {
        const now = std.time.timestamp();
        return self.batch_count >= self.config.batch_size or
            now - self.last_flush >= self.config.flush_interval_ms / 1000;
    }

    fn ensureConnection(self: *Self) !?std.net.Stream {
        const now = std.time.timestamp();

        // Check if we need to reconnect
        if (self.connection) |conn| {
            return conn;
        } else if (now < self.reconnect_time) {
            return null;
        }

        // Try to connect
        var stream = std.net.tcpConnectToHost(
            self.allocator,
            self.config.endpoint.host,
            self.config.endpoint.port,
        ) catch |err| {
            // Set reconnect time on failure
            self.reconnect_time = now + @divTrunc(@as(i64, @intCast(self.config.retry_delay_ms)), 1000);
            return err;
        };

        // Set up SSL if needed
        if (self.config.endpoint.secure) {
            // Note: SSL implementation would go here
            // For now, we'll just error out
            stream.close();
            return error.SslNotImplemented;
        }

        self.connection = stream;
        return stream;
    }
};
