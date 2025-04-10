const std = @import("std");
const nexlog = @import("nexlog");
const Logger = nexlog.Logger;
const types = nexlog.core.types;
const format = nexlog.utils.format;

pub fn main() !void {
    // Create a general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logs directory if it doesn't exist
    try std.fs.cwd().makePath("logs");

    // Initialize the logging system
    var builder = nexlog.LogBuilder.init();
    try builder
        .setMinLevel(.debug)
        .enableColors(true)
        .setBufferSize(8192)
        .enableFileLogging(true, "logs/app.log")
        .setMaxFileSize(5 * 1024 * 1024)
        .setMaxRotatedFiles(3)
        .enableRotation(true)
        .enableAsyncMode(true)
        .enableMetadata(true)
        .build(allocator);
    defer nexlog.deinit();

    // Get the default logger
    const log = nexlog.getDefaultLogger() orelse return error.LoggerNotInitialized;

    // Example 1: Basic structured logging
    try basicStructuredLogging(log, allocator);

    // Example 2: Structured logging with custom formatter
    try customFormatterLogging(log, allocator);

    // Example 3: Structured logging with multiple handlers
    try multiHandlerLogging(log, allocator);
}

fn basicStructuredLogging(log: *Logger, _: std.mem.Allocator) !void {
    std.debug.print("\n=== Basic Structured Logging ===\n", .{});

    // Create metadata
    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "main.zig",
        .line = 42,
        .function = "processRequest",
    };

    // Log with structured data
    log.info("User profile accessed", .{}, metadata);
}

fn customFormatterLogging(log: *Logger, allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Custom Formatter Logging ===\n", .{});

    // Create a custom formatter
    const formatter_config = format.FormatConfig{
        .structured_format = .logfmt,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };

    var formatter = try format.Formatter.init(allocator, formatter_config);
    defer formatter.deinit();

    // Create structured fields
    const fields = [_]format.StructuredField{
        .{
            .name = "user_id",
            .value = "12345",
            .attributes = null,
        },
        .{
            .name = "request_duration_ms",
            .value = "150",
            .attributes = null,
        },
        .{
            .name = "tags",
            .value = "api,v2",
            .attributes = null,
        },
    };

    // Create metadata
    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "main.zig",
        .line = 42,
        .function = "processRequest",
    };

    // Format the structured log entry
    const formatted = try formatter.formatStructured(
        .info,
        "User profile accessed",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);

    // Log the formatted entry
    log.info("{s}", .{formatted}, metadata);
}

fn multiHandlerLogging(log: *Logger, allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Multi-Handler Logging ===\n", .{});

    // Create a JSON formatter
    const json_config = format.FormatConfig{
        .structured_format = .json,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };

    var json_formatter = try format.Formatter.init(allocator, json_config);
    defer json_formatter.deinit();

    // Create a logfmt formatter
    const logfmt_config = format.FormatConfig{
        .structured_format = .logfmt,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };

    var logfmt_formatter = try format.Formatter.init(allocator, logfmt_config);
    defer logfmt_formatter.deinit();

    // Create structured fields
    const fields = [_]format.StructuredField{
        .{
            .name = "user_id",
            .value = "12345",
            .attributes = null,
        },
        .{
            .name = "request_duration_ms",
            .value = "150",
            .attributes = null,
        },
    };

    // Create metadata
    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "main.zig",
        .line = 42,
        .function = "processRequest",
    };

    // Format with JSON formatter
    const json_formatted = try json_formatter.formatStructured(
        .info,
        "User profile accessed",
        &fields,
        metadata,
    );
    defer allocator.free(json_formatted);

    // Format with logfmt formatter
    const logfmt_formatted = try logfmt_formatter.formatStructured(
        .info,
        "User profile accessed",
        &fields,
        metadata,
    );
    defer allocator.free(logfmt_formatted);

    // Log with both formats
    log.info("JSON: {s}", .{json_formatted}, metadata);
    log.info("Logfmt: {s}", .{logfmt_formatted}, metadata);
}
