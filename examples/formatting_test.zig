const std = @import("std");
const nexlog = @import("nexlog");
const format = nexlog.utils.format;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Testing Custom Formatting ===\n", .{});

    // Test 1: Default formatting
    std.debug.print("\n--- Test 1: Default Formatting ---\n", .{});
    try testDefaultFormatting(allocator);

    // Test 2: Custom template formatting
    std.debug.print("\n--- Test 2: Custom Template ---\n", .{});
    try testCustomTemplate(allocator);

    // Test 3: Different timestamp formats
    std.debug.print("\n--- Test 3: Timestamp Formats ---\n", .{});
    try testTimestampFormats(allocator);

    // Test 4: Level formatting options
    std.debug.print("\n--- Test 4: Level Formats ---\n", .{});
    try testLevelFormats(allocator);

    // Test 5: Color formatting
    std.debug.print("\n--- Test 5: Color Formatting ---\n", .{});
    try testColorFormatting(allocator);

    // Test 6: Custom placeholders (if implemented)
    std.debug.print("\n--- Test 6: Custom Placeholders ---\n", .{});
    try testCustomPlaceholders(allocator);
}

fn testDefaultFormatting(allocator: std.mem.Allocator) !void {
    const logger = try nexlog.Logger.init(allocator, .{});
    defer logger.deinit();

    const metadata = nexlog.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 12345,
        .file = "test.zig",
        .line = 42,
        .function = "testFunction",
    };

    try logger.log(.info, "Default formatting test", .{}, metadata);
    try logger.log(.warn, "Warning with default format", .{}, metadata);
    try logger.log(.err, "Error with default format", .{}, metadata);
}

fn testCustomTemplate(allocator: std.mem.Allocator) !void {
    // Create custom format config
    const custom_config = format.FormatConfig{
        .template = "{timestamp} | {level} | {file}:{line} | {function} | {message}",
        .timestamp_format = .unix,
        .level_format = .upper,
        .use_color = false,
    };

    const log_config = nexlog.LogConfig{
        .format_config = custom_config,
        .enable_colors = false,
    };

    const logger = try nexlog.Logger.init(allocator, log_config);
    defer logger.deinit();

    const metadata = nexlog.LogMetadata{
        .timestamp = 1640995200, // Fixed timestamp for consistency
        .thread_id = 12345,
        .file = "custom.zig",
        .line = 99,
        .function = "customTest",
    };

    try logger.log(.info, "Custom template test", .{}, metadata);
    try logger.log(.debug, "Debug with custom template", .{}, metadata);
}

fn testTimestampFormats(allocator: std.mem.Allocator) !void {
    // Test Unix timestamp
    const unix_config = format.FormatConfig{
        .template = "[{timestamp}] {level}: {message}",
        .timestamp_format = .unix,
        .use_color = false,
    };

    var formatter_unix = try format.Formatter.init(allocator, unix_config);
    defer formatter_unix.deinit();

    const metadata = nexlog.LogMetadata{
        .timestamp = 1640995200,
        .thread_id = 12345,
        .file = "test.zig",
        .line = 10,
        .function = "test",
    };

    const unix_result = try formatter_unix.format(.info, "Unix timestamp test", metadata);
    defer allocator.free(unix_result);
    std.debug.print("Unix: {s}\n", .{unix_result});

    // Test ISO8601 timestamp
    const iso_config = format.FormatConfig{
        .template = "[{timestamp}] {level}: {message}",
        .timestamp_format = .iso8601,
        .use_color = false,
    };

    var formatter_iso = try format.Formatter.init(allocator, iso_config);
    defer formatter_iso.deinit();

    const iso_result = try formatter_iso.format(.info, "ISO8601 timestamp test", metadata);
    defer allocator.free(iso_result);
    std.debug.print("ISO8601: {s}\n", .{iso_result});
}

fn testLevelFormats(allocator: std.mem.Allocator) !void {
    const levels = [_]nexlog.LogLevel{ .trace, .debug, .info, .warn, .err, .critical };

    // Test each level format individually
    const format_configs = [_]struct { name: []const u8, config: format.FormatConfig }{
        .{ .name = "UPPER", .config = .{ .template = "{level}: {message}", .level_format = .upper, .use_color = false } },
        .{ .name = "lower", .config = .{ .template = "{level}: {message}", .level_format = .lower, .use_color = false } },
        .{ .name = "SHORT_UPPER", .config = .{ .template = "{level}: {message}", .level_format = .short_upper, .use_color = false } },
        .{ .name = "short_lower", .config = .{ .template = "{level}: {message}", .level_format = .short_lower, .use_color = false } },
    };

    for (format_configs) |fmt_config| {
        std.debug.print("Format: {s}\n", .{fmt_config.name});

        var formatter = try format.Formatter.init(allocator, fmt_config.config);
        defer formatter.deinit();

        for (levels) |level| {
            const result = try formatter.format(level, "test message", null);
            defer allocator.free(result);
            std.debug.print("  {s}\n", .{result});
        }
        std.debug.print("\n", .{});
    }
}

fn testColorFormatting(allocator: std.mem.Allocator) !void {
    const config = format.FormatConfig{
        .template = "{color}{level}{reset}: {message}",
        .use_color = true,
    };

    var formatter = try format.Formatter.init(allocator, config);
    defer formatter.deinit();

    const levels = [_]nexlog.LogLevel{ .trace, .debug, .info, .warn, .err, .critical };

    for (levels) |level| {
        const result = try formatter.format(level, "Color test message", null);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    }
}

fn testCustomPlaceholders(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("Custom placeholder functionality not yet fully implemented\n", .{});
}
