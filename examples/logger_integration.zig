const std = @import("std");
const nexlog = @import("nexlog");

// Import Logger and core types
const Logger = nexlog.Logger;
const types = nexlog.core.types;
const format = nexlog.utils.format;
const LogLevel = nexlog.LogLevel; // Import LogLevel

// Import structured types (assuming re-exported from nexlog.zig)
const StructuredField = nexlog.StructuredField;
const FieldValue = nexlog.FieldValue;

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
        // .enableAsyncMode(true) // Keep async disabled for simpler example structure
        .enableMetadata(true)
        // Set default format to JSON for structured output
        .setFormatter(.{ .structured_format = .json })
        .build(allocator);
    defer nexlog.deinit();

    // Get the default logger
    const log = nexlog.getDefaultLogger() orelse return error.LoggerNotInitialized;

    // Example 1: Basic structured logging using the new logger method
    try basicStructuredLogging(log, allocator);

    // Example 2: Structured logging with a custom logfmt formatter (using formatter directly)
    try customFormatterLogging(log, allocator);

    // Example 3: Structured logging using the logger's direct API, output depends on logger config
    try multiHandlerLogging(log, allocator);
}

fn basicStructuredLogging(log: *Logger, allocator: std.mem.Allocator) !void {
    _ = allocator; // allocator might not be needed here anymore
    std.debug.print("\n=== Basic Structured Logging (using log.infoStructured) ===\n", .{});

    // Create metadata
    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "main.zig",
        .line = @src().line, // Get current line
        .function = "basicStructuredLogging",
    };

    // --- UPDATED fields definition ---
    const fields = [_]StructuredField{
        .{ .name = "user_id", .value = .{ .string = "basic_user" } },
        .{ .name = "action", .value = .{ .string = "login" } },
        .{ .name = "success", .value = .{ .boolean = true } },
    };

    // --- UPDATED: Use the new logStructured method (or convenience wrapper) ---
    // Using the try* variant for demonstration
    try log.tryInfoStructured(
        "User profile accessed", // Main message
        &fields, // Pass structured data
        metadata,
    );
    // Note: The infallible `log.infoStructured(...)` could also be used.
}

fn customFormatterLogging(log: *Logger, allocator: std.mem.Allocator) !void {
    _ = log; // log might not be needed if just demonstrating formatter
    std.debug.print("\n=== Custom Formatter Logging (Logfmt) ===\n", .{});

    // Create a custom formatter specifically for logfmt
    const formatter_config = format.FormatConfig{
        .structured_format = .logfmt,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };

    var formatter = try format.Formatter.init(allocator, formatter_config);
    defer formatter.deinit();

    // --- UPDATED fields definition ---
    const fields = [_]StructuredField{
        .{ .name = "user_id", .value = .{ .string = "fmt_user" } },
        .{ .name = "request_duration_ms", .value = .{ .integer = 150 } },
        .{ .name = "tags", .value = .{ .string = "api,v2" } }, // String needing quotes
    };

    // Create metadata
    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "main.zig",
        .line = @src().line,
        .function = "customFormatterLogging",
    };

    // --- UPDATED: Format the structured log entry using the new method ---
    const formatted = try formatter.formatStructuredWithFields(
        LogLevel.info,
        "User profile accessed",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);

    // Log the pre-formatted entry using the *basic* logger method
    // (This shows using the formatter directly)
    std.debug.print("Formatted Logfmt: {s}\n", .{formatted});
    // Or log it via nexlog if desired, though it's already formatted:
    // log.info("{s}", .{formatted}, metadata);
}

fn multiHandlerLogging(log: *Logger, allocator: std.mem.Allocator) !void {
    _ = allocator; // allocator not needed here
    std.debug.print("\n=== Multi-Handler Logging (using log.tryWarnStructured) ===\n", .{});
    std.debug.print("(Output format depends on logger's configuration)\n", .{});

    // The logger obtained from getDefaultLogger already has handlers configured
    // by the LogBuilder (Console and File, with default JSON format in this setup).
    // We just need to call the structured logging method.

    // --- UPDATED fields definition ---
    const fields = [_]StructuredField{
        .{ .name = "service", .value = .{ .string = "payment" } },
        .{ .name = "error_code", .value = .{ .integer = 503 } },
        .{ .name = "is_retryable", .value = .{ .boolean = true } },
        .{ .name = "details", .value = .{ .string = "Upstream timeout" } },
    };

    // Create metadata
    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 5678,
        .file = "services.zig",
        .line = @src().line,
        .function = "multiHandlerLogging",
    };

    // --- UPDATED: Log structured data directly using the logger's API ---
    // This will go to all configured handlers (Console, File)
    // and be formatted according to the logger's default formatter (JSON in this setup).
    try log.tryWarnStructured(
        "Service communication failed",
        &fields,
        metadata,
    );

    // If you wanted different formats *simultaneously* without reconfiguring the main logger,
    // you would need to create separate Formatter instances and format manually,
    // similar to the customFormatterLogging example.
}
