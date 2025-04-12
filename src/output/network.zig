const std = @import("std");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");
const buffer = @import("../utils/buffer.zig");
const expect = std.testing.expect;
const handlers = @import("handlers.zig");

pub const NetworkEndpoint = struct {
    host: []const u8,
    port: u16,
    secure: bool = false,
    path: []const u8 = "/logs",
};

pub const NetworkConfig = struct {
    endpoint: NetworkEndpoint,
    retry: RetryConfig = .{},
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

    retry_state: RetryState,

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
            .retry_state = .{},
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

    /// Convert to generic LogHandler interface
    pub fn toLogHandler(self: *Self) handlers.LogHandler {
        return handlers.LogHandler.init(
            self,
            .network,
            NetworkHandler.log,
            NetworkHandler.writeFormattedLog,
            NetworkHandler.flush,
            NetworkHandler.deinit,
        );
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

        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.retry_state.attempts < self.config.retry.max_attempts) {
            if (try self.ensureConnection()) |conn| {
                // Try to send the data
                self.sendBatch(conn) catch |err| {
                    self.retry_state.consecutive_failures += 1;
                    self.retry_state.attempts += 1;
                    self.retry_state.current_delay_ms = self.calculateNextDelay();

                    // If we've hit max attempts, propagate the error
                    if (self.retry_state.attempts >= self.config.retry.max_attempts) {
                        return err;
                    }

                    // Wait before retry
                    std.time.sleep(self.retry_state.current_delay_ms * std.time.ns_per_ms);
                    continue;
                };

                // Success! Reset retry state
                self.resetRetryState();
                return;
            }

            // Connection failed, update retry state
            self.retry_state.attempts += 1;
            self.retry_state.current_delay_ms = self.calculateNextDelay();

            if (self.retry_state.attempts >= self.config.retry.max_attempts) {
                return error.NetworkError;
            }

            std.time.sleep(self.retry_state.current_delay_ms * std.time.ns_per_ms);
        }

        return error.NetworkError;
    }

    fn shouldFlush(self: *Self) bool {
        const now = std.time.timestamp();
        return self.batch_count >= self.config.batch_size or
            now - self.last_flush >= self.config.flush_interval_ms / 1000;
    }

    fn sendBatch(self: *Self, conn: std.net.Stream) !void {
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
    }

    fn ensureConnection(self: *Self) !std.net.Stream {
        const now = std.time.timestamp();

        // Check if we need to reconnect
        if (self.connection) |conn| {
            return conn;
        } else if (now < self.reconnect_time) {
            return error.ReconnectPending;
        }

        // Try to connect
        var stream = std.net.tcpConnectToHost(
            self.allocator,
            self.config.endpoint.host,
            self.config.endpoint.port,
        ) catch |err| {
            std.log.err("Failed to connect to {}:{} - {}", .{ self.config.endpoint.host, self.config.endpoint.port, err });
            // Set reconnect time on failure
            self.reconnect_time = now + @divTrunc(@as(i64, @intCast(self.config.retry_delay_ms)), 1000);
            return err;
        };

        // Set up SSL if needed
        if (self.config.endpoint.secure) {
            // Note: SSL implementation would go here
            // For now, we'll just error out
            std.log.warn("SSL is not implemented yet, closing connection.");
            stream.close();
            return error.SslNotImplemented;
        }

        self.connection = stream;
        return stream;
    }

    fn calculateNextDelay(self: *Self) u32 {
        const config = self.config.retry;
        var delay: u32 = switch (config.strategy) {
            .constant => config.initial_delay_ms,
            .linear => config.initial_delay_ms * (self.retry_state.attempts + 1),
            .exponential => config.initial_delay_ms * std.math.pow(u32, 2, self.retry_state.attempts),
        };

        // Apply max delay limit
        delay = @min(delay, config.max_delay_ms);

        // Add jitter
        if (config.jitter_factor > 0) {
            const jitter_range: f32 = @as(f32, @floatFromInt(delay)) * config.jitter_factor;
            if (jitter_range > 0) {
                var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
                delay += @intFromFloat(prng.random().float(f32) * jitter_range);
            }
        }

        return delay;
    }

    fn resetRetryState(self: *Self) void {
        self.retry_state = .{
            .attempts = 0,
            .last_attempt = std.time.timestamp(),
            .current_delay_ms = self.config.retry.initial_delay_ms,
            .consecutive_failures = 0,
        };
    }
};

pub const RetryStrategy = enum {
    constant,
    exponential,
    linear,
};

pub const RetryConfig = struct {
    strategy: RetryStrategy = .exponential,
    initial_delay_ms: u32 = 100,
    max_delay_ms: u32 = 30_000,
    max_attempts: u32 = 5,
    jitter_factor: f32 = 0.1,
};

pub const RetryState = struct {
    attempts: u32 = 0,
    last_delay: u32 = 0,
    current_delay: u32 = 0,
    consecutive_failures: u32 = 0,
};

test "NetworkHandler initialization and deinitialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const config = NetworkConfig{
        .endpoint = .{
            .host = "example.com",
            .port = 8080,
        },
    };

    var handler = try NetworkHandler.init(allocator, config);
    defer handler.deinit();

    try expect(handler.config.endpoint.host.len == config.endpoint.host.len);
    try expect(handler.config.endpoint.port == config.endpoint.port);
    try expect(handler.circular_buffer.buffer.len == config.buffer_size);
}

test "NetworkHandler retry strategies" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Test configuration
    const config = NetworkConfig{
        .endpoint = .{
            .host = "localhost",
            .port = 8080,
        },
        .retry = .{
            .strategy = .exponential,
            .initial_delay_ms = 10,
            .max_delay_ms = 1000,
            .max_attempts = 3,
            .jitter_factor = 0.1,
        },
    };

    var handler = try NetworkHandler.init(allocator, config);
    defer handler.deinit();

    // Test delay calculations
    {
        // Test initial delay
        try expect(handler.calculateNextDelay() == 10);

        // Test exponential backoff
        handler.retry_state.attempts = 1;
        const delay1 = handler.calculateNextDelay();
        try expect(delay1 >= 20 and delay1 <= 22); // Account for jitter

        handler.retry_state.attempts = 2;
        const delay2 = handler.calculateNextDelay();
        try expect(delay2 >= 40 and delay2 <= 44); // Account for jitter

        // Test max delay limit
        handler.retry_state.attempts = 10; // Should hit max_delay_ms
        try expect(handler.calculateNextDelay() <= config.retry.max_delay_ms);
    }

    // Test retry state management
    {
        handler.resetRetryState();
        try expect(handler.retry_state.attempts == 0);
        try expect(handler.retry_state.consecutive_failures == 0);
        try expect(handler.retry_state.current_delay_ms == config.retry.initial_delay_ms);
    }
}

test "NetworkHandler retry strategies comparison" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Test different strategies
    const strategies = [_]RetryStrategy{ .constant, .linear, .exponential };
    for (strategies) |strategy| {
        const config = NetworkConfig{
            .endpoint = .{
                .host = "localhost",
                .port = 8080,
            },
            .retry = .{
                .strategy = strategy,
                .initial_delay_ms = 10,
                .max_delay_ms = 1000,
                .max_attempts = 3,
                .jitter_factor = 0, // Disable jitter for predictable testing
            },
        };

        var handler = try NetworkHandler.init(allocator, config);
        defer handler.deinit();

        // Test progression of delays
        var last_delay: u32 = 0;
        var i: u32 = 0;
        while (i < 3) : (i += 1) {
            handler.retry_state.attempts = i;
            const current_delay = handler.calculateNextDelay();

            switch (strategy) {
                .constant => {
                    try expect(current_delay == config.retry.initial_delay_ms);
                },
                .linear => {
                    try expect(current_delay == config.retry.initial_delay_ms * (i + 1));
                },
                .exponential => {
                    try expect(current_delay == config.retry.initial_delay_ms * std.math.pow(u32, 2, i));
                },
            }

            if (i > 0) {
                switch (strategy) {
                    .constant => try expect(current_delay == last_delay),
                    .linear => try expect(current_delay > last_delay),
                    .exponential => try expect(current_delay > last_delay),
                }
            }

            last_delay = current_delay;
        }
    }
}

test "NetworkHandler retry with mock connection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const config = NetworkConfig{
        .endpoint = .{
            .host = "localhost",
            .port = 8080,
        },
        .retry = .{
            .strategy = .constant,
            .initial_delay_ms = 1,
            .max_delay_ms = 10,
            .max_attempts = 3,
            .jitter_factor = 0,
        },
    };

    var handler = try NetworkHandler.init(allocator, config);
    defer handler.deinit();

    // Add some test data
    try handler.write(.info, "test message", null);
    try expect(handler.batch_count == 1);

    // Attempt flush (will fail due to no real connection)
    handler.flush() catch |err| {
        try expect(err == error.NetworkError);
        try expect(handler.retry_state.attempts == config.retry.max_attempts);
        try expect(handler.retry_state.consecutive_failures > 0);
    };
}

test "NetworkHandler jitter behavior" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const config = NetworkConfig{
        .endpoint = .{
            .host = "localhost",
            .port = 8080,
        },
        .retry = .{
            .strategy = .constant,
            .initial_delay_ms = 100,
            .max_delay_ms = 1000,
            .max_attempts = 3,
            .jitter_factor = 0.5, // 50% jitter
        },
    };

    var handler = try NetworkHandler.init(allocator, config);
    defer handler.deinit();

    // Test that jitter produces different delays
    var delays = std.ArrayList(u32).init(allocator);
    defer delays.deinit();

    // Calculate multiple delays and ensure they're different
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const delay = handler.calculateNextDelay();
        try delays.append(delay);
        // Verify delay is within jitter bounds
        try expect(delay >= config.retry.initial_delay_ms * 0.5);
        try expect(delay <= config.retry.initial_delay_ms * 1.5);
    }

    // Verify that at least some delays are different (jitter working)
    var all_same = true;
    const first_delay = delays.items[0];
    for (delays.items[1..]) |delay| {
        if (delay != first_delay) {
            all_same = false;
            break;
        }
    }
    try expect(!all_same);
}
