# Structured Logging in NexLog

NexLog provides powerful structured logging capabilities that allow you to include rich, type-safe data in your log entries. This document explains how to use structured logging in your applications.

## Overview

Structured logging allows you to include additional context with your log messages in a format that's easily parseable by log aggregation tools. NexLog supports multiple output formats:

- **JSON**: Standard JSON format for maximum compatibility
- **Logfmt**: Key=value format for human readability and easy parsing
- **Custom**: Configurable format with custom separators

## Basic Usage

### Creating Structured Fields

```zig
// Create structured fields
const fields = [_]format.StructuredField{
    .{
        .name = "user_id",
        .value = .{ .string = "12345" },
        .attributes = null,
    },
    .{
        .name = "request_duration_ms",
        .value = .{ .integer = 150 },
        .attributes = null,
    },
    .{
        .name = "tags",
        .value = .{ .array = &[_]format.FieldValue{
            .{ .string = "api" },
            .{ .string = "v2" },
        }},
        .attributes = null,
    },
};
```

### Supported Field Types

NexLog supports a variety of field types:

- **String**: Text values
- **Integer**: 64-bit signed integers
- **Float**: 64-bit floating point numbers
- **Boolean**: True/false values
- **Array**: Lists of values
- **Object**: Nested key-value structures
- **Null**: Explicit null values

### Formatting Options

You can configure the formatter with different options:

```zig
// JSON format
const json_config = format.FormatConfig{
    .structured_format = .json,
    .include_timestamp_in_structured = true,
    .include_level_in_structured = true,
};

// Logfmt format
const logfmt_config = format.FormatConfig{
    .structured_format = .logfmt,
    .include_timestamp_in_structured = true,
    .include_level_in_structured = true,
};

// Custom format
const custom_config = format.FormatConfig{
    .structured_format = .custom,
    .include_timestamp_in_structured = true,
    .include_level_in_structured = true,
    .custom_field_separator = " | ",
    .custom_key_value_separator = ": ",
};
```

## Examples

### JSON Output

```json
{"timestamp":1234567890,"level":"INFO","message":"User profile accessed","user_id":"12345","request_duration_ms":150,"tags":["api","v2"]}
```

### Logfmt Output

```
timestamp=1234567890 level=INFO msg="User profile accessed" user_id=12345 request_duration_ms=150 tags=[api,v2]
```

### Custom Format Output

```
timestamp: 1234567890 | level: INFO | msg: User profile accessed | user_id: 12345 | request_duration_ms: 150 | tags: [api, v2]
```

## Advanced Features

### Nested Structures

You can include nested objects and arrays in your structured logs:

```zig
// Create a nested object
var user_data = std.StringHashMap(format.FieldValue).init(allocator);
defer user_data.deinit();
try user_data.put("id", .{ .string = "12345" });
try user_data.put("name", .{ .string = "John Doe" });
try user_data.put("age", .{ .integer = 30 });
try user_data.put("active", .{ .boolean = true });

// Create structured fields with nested structures
const fields = [_]format.StructuredField{
    .{
        .name = "user",
        .value = .{ .object = user_data },
        .attributes = null,
    },
    // ... other fields
};
```

### Field Attributes

You can add additional attributes to fields for more context:

```zig
// Create a field with attributes
var attrs = std.StringHashMap([]const u8).init(allocator);
try attrs.put("source", "database");
try attrs.put("format", "uuid");

const field = format.StructuredField{
    .name = "user_id",
    .value = .{ .string = "12345" },
    .attributes = attrs,
};
```

## Integration with Logger

You can integrate structured logging with the main logger:

```zig
// Create a formatter
var formatter = try format.Formatter.init(allocator, config);
defer formatter.deinit();

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
```

## Best Practices

1. **Use meaningful field names**: Choose descriptive names that clearly indicate what the data represents.
2. **Include context**: Add relevant context like user IDs, request IDs, and timestamps.
3. **Be consistent**: Use consistent field names and types across your application.
4. **Keep it simple**: Don't over-complicate your log structure - focus on the most important information.
5. **Consider performance**: For high-volume logging, be mindful of memory allocations and string formatting. 