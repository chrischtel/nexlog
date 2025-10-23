const std = @import("std");
const nexlog = @import("nexlog");

// Import the necessary types directly via nexlog (assuming re-export)
// If not re-exported, use: const types = @import("nexlog").core.types;
const format = nexlog.utils.format;
const types = nexlog.core.types;
const StructuredField = nexlog.StructuredField;
const FieldValue = nexlog.FieldValue;
const LogLevel = nexlog.LogLevel; // Import LogLevel for clarity

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

    // Example 4: Mixed data types (previously nested structures example, now using FieldValue)
    try mixedDataTypesExample(allocator); // Renamed for clarity
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

    // --- UPDATED fields definition ---
    const fields = [_]StructuredField{
        .{ .name = "user_id", .value = .{ .string = "12345" } },
        .{ .name = "request_duration_ms", .value = .{ .integer = 150 } }, // Use integer
        .{ .name = "success", .value = .{ .boolean = true } }, // Use boolean
        .{ .name = "retry_attempt", .value = .{ .null = {} } }, // Use null
        .{ .name = "response_code", .value = .{ .integer = 200 } },
        .{ .name = "tags", .value = .{ .string = "api,v2" } }, // Keep as string
    };

    // Create metadata
    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "main.zig",
        .line = 42,
        .function = "processRequest",
    };

    // --- UPDATED formatter call ---
    const formatted = try formatter.formatStructuredWithFields(
        LogLevel.info, // Pass LogLevel directly
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

    // --- UPDATED fields definition ---
    const fields = [_]StructuredField{
        .{ .name = "user_id", .value = .{ .string = "12345" } },
        .{ .name = "request_duration_ms", .value = .{ .integer = 150 } }, // Use integer
        .{ .name = "success", .value = .{ .boolean = true } }, // Use boolean
        .{ .name = "tags", .value = .{ .string = "api,v2" } }, // String needing potential quotes
        .{ .name = "ip_address", .value = .{ .string = "192.168.1.10" } }, // String not needing quotes
    };

    // Create metadata
    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "main.zig",
        .line = 42,
        .function = "processRequest",
    };

    // --- UPDATED formatter call ---
    const formatted = try formatter.formatStructuredWithFields(
        LogLevel.info,
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

    // --- UPDATED fields definition ---
    const fields = [_]StructuredField{
        .{ .name = "user_id", .value = .{ .string = "12345" } },
        .{ .name = "request_duration_ms", .value = .{ .integer = 150 } }, // Use integer
        .{ .name = "tags", .value = .{ .string = "api,v2" } },
    };

    // Create metadata
    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "main.zig",
        .line = 42,
        .function = "processRequest",
    };

    // --- UPDATED formatter call ---
    const formatted = try formatter.formatStructuredWithFields(
        LogLevel.info,
        "User profile accessed",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);

    std.debug.print("{s}\n", .{formatted});
}

// Renamed from nestedStructuresExample
fn mixedDataTypesExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Mixed Data Types Example (JSON Output) ===\n", .{});

    // Configure formatter for JSON output
    const config = format.FormatConfig{
        .structured_format = .json,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };

    var formatter = try format.Formatter.init(allocator, config);
    defer formatter.deinit();

    // --- UPDATED fields definition with various FieldValue types ---
    // Note: The previous example used pre-formatted JSON strings.
    // Now we represent the data more natively.
    // If you need actual nested objects/arrays, the FieldValue union needs those variants.
    // For now, keeping them as strings but showing other types too.
    const fields = [_]StructuredField{
        .{ .name = "user_id", .value = .{ .integer = 12345 } },
        .{ .name = "user_name", .value = .{ .string = "John Doe" } },
        .{ .name = "age", .value = .{ .integer = 30 } },
        .{ .name = "active", .value = .{ .boolean = true } },
        .{ .name = "balance", .value = .{ .float = 123.45 } },
        .{ .name = "permissions", .value = .{ .string = "[\"read\",\"write\",\"admin\"]" } }, // Still string
        .{ .name = "last_login", .value = .{ .null = {} } },
        .{ .name = "request_details", .value = .{ .string = "{\"method\":\"GET\",\"path\":\"/api/users\",\"duration_ms\":150}" } }, // Still string
    };

    // Create metadata
    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "main.zig",
        .line = 42,
        .function = "processRequest",
    };

    // --- UPDATED formatter call ---
    const formatted = try formatter.formatStructuredWithFields(
        LogLevel.info,
        "Complex data types example",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);

    std.debug.print("{s}\n", .{formatted});
}
