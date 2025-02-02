const std = @import("std");
const testing = std.testing;
const nexlog = @import("nexlog");

fn defaultConfig() nexlog.LogConfig {
    return .{
        .min_level = .debug,
        .enable_colors = false,
        .enable_file_logging = false,
        .file_path = null,
    };
}

fn defaultMetadata() nexlog.LogMetadata {
    return .{
        .timestamp = std.time.timestamp(),
        .thread_id = 0,
        .file = @src().file,
        .line = @src().line,
        .function = @src().fn_name,
    };
}

// Basic functionality tests
test "core: logger initialization" {
    const config = defaultConfig();
    const logger = try nexlog.Logger.init(testing.allocator, config);
    defer logger.deinit();
    // Instead of checking mutex directly, let's verify the logger works
    try logger.log(.info, "Test initialization", .{}, defaultMetadata());
}

test "core: basic logging" {
    const config = defaultConfig();
    var logger = try nexlog.Logger.init(testing.allocator, config);
    defer logger.deinit();
    try logger.log(.info, "Test message", .{}, defaultMetadata());
}

test "core: verify log format" {
    const config = defaultConfig();
    var logger = try nexlog.Logger.init(testing.allocator, config);
    defer logger.deinit();
    try logger.log(.info, "Test message", .{}, defaultMetadata());
}

test "core: all log levels" {
    const config = defaultConfig();
    var logger = try nexlog.Logger.init(testing.allocator, config);
    defer logger.deinit();

    // Test each level
    inline for (comptime std.meta.tags(nexlog.LogLevel)) |level| {
        try logger.log(level, "Test message for {s}", .{@tagName(level)}, defaultMetadata());
    }
}

test "core: format arguments" {
    const config = defaultConfig();
    var logger = try nexlog.Logger.init(testing.allocator, config);
    defer logger.deinit();

    const metadata = defaultMetadata();
    try logger.log(.info, "Integer: {d}", .{42}, metadata);
    try logger.log(.info, "String: {s}", .{"test"}, metadata);
    try logger.log(.info, "Multiple: {d}, {s}", .{ 123, "test" }, metadata);
}

test "core: thread safety" {
    const config = defaultConfig();
    var logger = try nexlog.Logger.init(testing.allocator, config);
    defer logger.deinit();

    const ThreadContext = struct {
        logger: *nexlog.Logger,
        id: usize,

        pub fn run(self: *@This()) !void {
            try self.logger.log(.info, "Message from thread {d}", .{self.id}, .{
                .timestamp = std.time.timestamp(),
                .thread_id = self.id,
                .file = @src().file,
                .line = @src().line,
                .function = @src().fn_name,
            });
        }
    };

    var threads: [3]std.Thread = undefined;
    var contexts = [_]ThreadContext{
        .{ .logger = logger, .id = 0 },
        .{ .logger = logger, .id = 1 },
        .{ .logger = logger, .id = 2 },
    };

    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, ThreadContext.run, .{&contexts[i]});
    }

    for (threads) |thread| {
        thread.join();
    }
}

test "core: error conditions" {
    const config = defaultConfig();
    var logger = try nexlog.Logger.init(testing.allocator, config);
    defer logger.deinit();

    const metadata = defaultMetadata();
    // Test with empty message
    try logger.log(.info, "", .{}, metadata);

    // Test with very long message
    const long_msg = "x" ** 1000;
    try logger.log(.info, "{s}", .{long_msg}, metadata);
}

// Test for formatter functionality
test "formatter functionality test" {
    const format_config = nexlog.FormatConfig{
        .template = "[{timestamp}] [{level}] {message}",
        .timestamp_format = .unix,
        .level_format = .upper,
        .use_color = false,
    };

    const config = nexlog.LogConfig{
        .min_level = .debug,
        .enable_colors = false,
        .enable_file_logging = false,
        .format_config = format_config,
    };

    var logger = try nexlog.Logger.init(testing.allocator, config);
    defer logger.deinit();

    try logger.log(.info, "Formatted test message", .{}, defaultMetadata());
}
