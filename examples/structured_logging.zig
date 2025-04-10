const std = @import("std");
const nexlog = @import("nexlog");
const format = nexlog.utils.format;
const types = nexlog.core.types;

pub fn main() !void {
    // Create a general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example 1: JSON format
    try jsonExample(allocator);

    // Example 2: Logfmt format
    try logfmtExample(allocator);

    // Example 3: Custom format
    try customFormatExample(allocator);

    // Example 4: Complex nested structures
    try nestedStructuresExample(allocator);
}

fn jsonExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== JSON Format Example ===\n", .{});

    // Configure formatter for JSON output
    const config = format.FormatConfig{
        .structured_format = .json,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };

    var formatter = try format.Formatter.init(allocator, config);
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

    // Format the log entry
    const formatted = try formatter.formatStructured(
        .info,
        "User profile accessed",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);

    std.debug.print("{s}\n", .{formatted});
}

fn logfmtExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Logfmt Format Example ===\n", .{});

    // Configure formatter for logfmt output
    const config = format.FormatConfig{
        .structured_format = .logfmt,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };

    var formatter = try format.Formatter.init(allocator, config);
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

    // Format the log entry
    const formatted = try formatter.formatStructured(
        .info,
        "User profile accessed",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);

    std.debug.print("{s}\n", .{formatted});
}

fn customFormatExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Custom Format Example ===\n", .{});

    // Configure formatter for custom output
    const config = format.FormatConfig{
        .structured_format = .custom,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
        .custom_field_separator = " | ",
        .custom_key_value_separator = ": ",
    };

    var formatter = try format.Formatter.init(allocator, config);
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

    // Format the log entry
    const formatted = try formatter.formatStructured(
        .info,
        "User profile accessed",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);

    std.debug.print("{s}\n", .{formatted});
}

fn nestedStructuresExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Nested Structures Example ===\n", .{});

    // Configure formatter for JSON output
    const config = format.FormatConfig{
        .structured_format = .json,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };

    var formatter = try format.Formatter.init(allocator, config);
    defer formatter.deinit();

    // Create structured fields with nested structures
    const fields = [_]format.StructuredField{
        .{
            .name = "user",
            .value = "{\"id\":\"12345\",\"name\":\"John Doe\",\"age\":30,\"active\":true}",
            .attributes = null,
        },
        .{
            .name = "permissions",
            .value = "[\"read\",\"write\",\"admin\"]",
            .attributes = null,
        },
        .{
            .name = "request",
            .value = "{\"method\":\"GET\",\"path\":\"/api/users\",\"duration_ms\":150}",
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

    // Format the log entry
    const formatted = try formatter.formatStructured(
        .info,
        "Complex nested structure example",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);

    std.debug.print("{s}\n", .{formatted});
}
