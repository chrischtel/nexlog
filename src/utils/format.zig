// utils/format.zig
const std = @import("std");
const types = @import("../core/types.zig");

pub const StructuredField = struct {
    name: []const u8,
    value: []const u8,
    attributes: ?std.StringHashMap(u8) = null,
};

pub const FieldValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: []const FieldValue,
    object: std.StringHashMap(FieldValue),
    null,

    pub fn format(self: FieldValue, writer: *std.Io.Writer) !void {
        switch (self) {
            .string => |str| try writer.print("\"{s}\"", .{str}),
            .integer => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .boolean => |b| try writer.print("{}", .{b}),
            .array => |arr| {
                try writer.writeAll("[");
                for (arr, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(writer);
                }
                try writer.writeAll("]");
            },
            .object => |map| {
                try writer.writeAll("{");
                var it = map.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) try writer.writeAll(", ");
                    try writer.print("\"{s}\": ", .{entry.key_ptr.*});
                    try entry.value_ptr.*.format(writer);
                    first = false;
                }
                try writer.writeAll("}");
            },
            .null => try writer.writeAll("null"),
        }
    }
};

/// Format placeholder types
pub const PlaceholderType = enum {
    level,
    message,
    timestamp,
    thread,
    file,
    line,
    function,
    color,
    reset,
    // Context placeholders
    request_id,
    correlation_id,
    trace_id,
    span_id,
    user_id,
    session_id,
    operation,
    component,
    custom,
};

/// Format configuration
pub const FormatConfig = struct {
    /// Default format: "[{timestamp}] [{level}] {message}"
    template: []const u8 = "[{timestamp}] [{level}] {message}",

    timestamp_format: enum {
        unix,
        iso8601,
        custom,
    } = .unix,
    custom_timestamp_format: ?[]const u8 = null,

    level_format: enum {
        upper, // "ERROR"
        lower, // "error"
        short_upper, // "ERR"
        short_lower, // "err"
    } = .upper,

    use_color: bool = true,
    custom_colors: ?std.StringHashMap([]const u8) = null,

    /// Custom placeholder handlers
    custom_handlers: ?std.StringHashMap(CustomPlaceholderFn) = null,

    structured_format: enum {
        json, // Output as JSON
        logfmt, // Key=value format
        custom, // Custom format
    } = .json,

    include_timestamp_in_structured: bool = true,
    include_level_in_structured: bool = true,
    custom_field_separator: ?[]const u8 = null,
    custom_key_value_separator: ?[]const u8 = null,

    /// Stack buffer size for avoiding heap allocations on common log sizes
    /// Default 1KB should handle most log entries without heap allocation
    stack_buffer_size: usize = 1024,

    /// Stack buffer size for structured logs (typically larger)
    structured_stack_buffer_size: usize = 2048,
};

/// Function type for custom placeholder handlers
pub const CustomPlaceholderFn = *const fn (
    allocator: std.mem.Allocator,
    level: types.LogLevel,
    message: []const u8,
    metadata: ?types.LogMetadata,
) error{OutOfMemory}![]const u8;

/// Parsed placeholder information
const Placeholder = struct {
    type: PlaceholderType,
    start: usize,
    end: usize,
    format: ?[]const u8,
};

// utils/format.zig (continued)

/// Error set for format operations
pub const FormatError = error{
    InvalidPlaceholder,
    InvalidFormat,
    MissingHandler,
    TimestampError,
};

pub const Formatter = struct {
    allocator: std.mem.Allocator,
    config: FormatConfig,
    placeholder_cache: std.ArrayList(Placeholder),

    pub fn init(allocator: std.mem.Allocator, config: FormatConfig) !*Formatter {
        var self = try allocator.create(Formatter);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .placeholder_cache = .empty,
        };
        // Parse template once during initialization
        try self.parsePlaceholders();
        return self;
    }

    pub fn deinit(self: *Formatter) void {
        self.placeholder_cache.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn parsePlaceholders(self: *Formatter) !void {
        var i: usize = 0;
        while (i < self.config.template.len) {
            if (self.config.template[i] == '{') {
                const start = i;
                i += 1;
                var found_end = false;
                var fmt_spec: ?[]const u8 = null;

                // Look for format specifier
                while (i < self.config.template.len) : (i += 1) {
                    if (self.config.template[i] == ':') {
                        // Extract format string
                        const format_start = i + 1;
                        while (i < self.config.template.len and self.config.template[i] != '}') : (i += 1) {}
                        fmt_spec = self.config.template[format_start..i];
                        found_end = true;
                        break;
                    } else if (self.config.template[i] == '}') {
                        found_end = true;
                        break;
                    }
                }

                if (!found_end) {
                    return FormatError.InvalidPlaceholder;
                }

                const placeholder_name = self.config.template[start + 1 .. if (fmt_spec == null) i else i - fmt_spec.?.len - 1];
                const placeholder_type = try self.getPlaceholderType(placeholder_name);

                try self.placeholder_cache.append(self.allocator, .{
                    .type = placeholder_type,
                    .start = start,
                    .end = i + 1,
                    .format = fmt_spec,
                });
            }
            i += 1;
        }
    }

    fn getPlaceholderType(self: *Formatter, name: []const u8) !PlaceholderType {
        if (std.mem.eql(u8, name, "level")) return .level;
        if (std.mem.eql(u8, name, "message")) return .message;
        if (std.mem.eql(u8, name, "timestamp")) return .timestamp;
        if (std.mem.eql(u8, name, "thread")) return .thread;
        if (std.mem.eql(u8, name, "file")) return .file;
        if (std.mem.eql(u8, name, "line")) return .line;
        if (std.mem.eql(u8, name, "function")) return .function;
        if (std.mem.eql(u8, name, "color")) return .color;
        if (std.mem.eql(u8, name, "reset")) return .reset;

        // Context placeholders
        if (std.mem.eql(u8, name, "request_id")) return .request_id;
        if (std.mem.eql(u8, name, "correlation_id")) return .correlation_id;
        if (std.mem.eql(u8, name, "trace_id")) return .trace_id;
        if (std.mem.eql(u8, name, "span_id")) return .span_id;
        if (std.mem.eql(u8, name, "user_id")) return .user_id;
        if (std.mem.eql(u8, name, "session_id")) return .session_id;
        if (std.mem.eql(u8, name, "operation")) return .operation;
        if (std.mem.eql(u8, name, "component")) return .component;

        // Check for custom placeholder
        if (self.config.custom_handlers) |handlers| {
            if (handlers.contains(name)) {
                return .custom;
            }
        }

        return FormatError.InvalidPlaceholder;
    }

    pub fn format(
        self: *Formatter,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) ![]const u8 {
        // Use a reasonable fixed stack buffer size that should handle most logs
        // Users can configure larger sizes via formatWithBuffer() if needed
        var stack_buffer: [1024]u8 = undefined;
        return self.formatWithBuffer(&stack_buffer, level, message, metadata);
    }

    /// Format with a provided buffer, falling back to heap if buffer is too small
    pub fn formatWithBuffer(
        self: *Formatter,
        buffer: []u8,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) ![]const u8 {
        var fba = std.heap.FixedBufferAllocator.init(buffer);
        const stack_allocator = fba.allocator();

        var result: std.Io.Writer.Allocating = .init(stack_allocator);

        var last_pos: usize = 0;

        // Format using stack buffer
        const format_result = blk: {
            for (self.placeholder_cache.items) |placeholder| {
                // Add text before placeholder
                result.writer.writeAll(self.config.template[last_pos..placeholder.start]) catch break :blk null;

                // Format placeholder
                self.formatPlaceholder(
                    &result.writer,
                    placeholder,
                    level,
                    message,
                    metadata,
                ) catch break :blk null;

                last_pos = placeholder.end;
            }

            // Add remaining text after last placeholder
            result.writer.writeAll(self.config.template[last_pos..]) catch break :blk null;

            // Success! Return stack-allocated result
            break :blk result.written();
        };

        if (format_result) |stack_result| {
            // Stack allocation succeeded, copy to owned slice
            return self.allocator.dupe(u8, stack_result);
        }

        // Stack buffer too small, fall back to heap allocation
        result.deinit(); // Clean up failed stack attempt
        result = .init(self.allocator);
        errdefer result.deinit();

        last_pos = 0;
        for (self.placeholder_cache.items) |placeholder| {
            // Add text before placeholder
            try result.writer.writeAll(self.config.template[last_pos..placeholder.start]);

            // Format placeholder
            try self.formatPlaceholder(
                &result.writer,
                placeholder,
                level,
                message,
                metadata,
            );

            last_pos = placeholder.end;
        }

        // Add remaining text after last placeholder
        try result.writer.writeAll(self.config.template[last_pos..]);

        return result.toOwnedSlice();
    }

    fn formatPlaceholder(
        self: *Formatter,
        writer: *std.Io.Writer,
        placeholder: Placeholder,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) !void {
        switch (placeholder.type) {
            .level => try self.formatLevel(writer, level),
            .message => try writer.writeAll(message),
            .timestamp => try self.formatTimestamp(writer, metadata),
            .thread => if (metadata) |m| try writer.print("{d}", .{m.thread_id}),
            .file => if (metadata) |m| try writer.writeAll(m.file),
            .line => if (metadata) |m| try writer.print("{d}", .{m.line}),
            .function => if (metadata) |m| try writer.writeAll(m.function),
            .color => if (self.config.use_color) try writer.writeAll(level.toColor()),
            .reset => if (self.config.use_color) try writer.writeAll("\x1b[0m"),

            // Context placeholders
            .request_id => try self.formatContextField(writer, metadata, "request_id"),
            .correlation_id => try self.formatContextField(writer, metadata, "correlation_id"),
            .trace_id => try self.formatContextField(writer, metadata, "trace_id"),
            .span_id => try self.formatContextField(writer, metadata, "span_id"),
            .user_id => try self.formatContextField(writer, metadata, "user_id"),
            .session_id => try self.formatContextField(writer, metadata, "session_id"),
            .operation => try self.formatContextField(writer, metadata, "operation"),
            .component => try self.formatContextField(writer, metadata, "component"),

            .custom => try self.formatCustomPlaceholder(writer, placeholder, level, message, metadata),
        }
    }

    /// Helper function to format context fields
    fn formatContextField(
        self: *Formatter,
        writer: *std.Io.Writer,
        metadata: ?types.LogMetadata,
        field_name: []const u8,
    ) !void {
        _ = self; // suppress unused parameter warning

        if (metadata) |m| {
            if (m.context) |context| {
                const field_value = if (std.mem.eql(u8, field_name, "request_id"))
                    context.request_id
                else if (std.mem.eql(u8, field_name, "correlation_id"))
                    context.correlation_id
                else if (std.mem.eql(u8, field_name, "trace_id"))
                    context.trace_id
                else if (std.mem.eql(u8, field_name, "span_id"))
                    context.span_id
                else if (std.mem.eql(u8, field_name, "user_id"))
                    context.user_id
                else if (std.mem.eql(u8, field_name, "session_id"))
                    context.session_id
                else if (std.mem.eql(u8, field_name, "operation"))
                    context.operation
                else if (std.mem.eql(u8, field_name, "component"))
                    context.function // Map component to function field
                else
                    null;

                if (field_value) |value| {
                    try writer.writeAll(value);
                } else {
                    try writer.writeByte('-'); // Default placeholder for missing values
                }
            } else {
                try writer.writeByte('-'); // No context available
            }
        } else {
            try writer.writeByte('-'); // No metadata available
        }
    }

    pub fn formatStructured(
        self: *Formatter,
        level: types.LogLevel,
        message: []const u8,
        fields: []const StructuredField,
        metadata: ?types.LogMetadata,
    ) ![]const u8 {
        // Use a larger stack buffer for structured logs (JSON can be verbose)
        var stack_buffer: [2048]u8 = undefined;
        return self.formatStructuredWithBuffer(&stack_buffer, level, message, fields, metadata);
    }

    /// Format structured with a provided buffer, falling back to heap if buffer is too small
    pub fn formatStructuredWithBuffer(
        self: *Formatter,
        buffer: []u8,
        level: types.LogLevel,
        message: []const u8,
        fields: []const StructuredField,
        metadata: ?types.LogMetadata,
    ) ![]const u8 {
        var fba = std.heap.FixedBufferAllocator.init(buffer);
        const stack_allocator = fba.allocator();

        var result: std.Io.Writer.Allocating = .init(stack_allocator);

        // Format using stack buffer
        const format_result = blk: {
            switch (self.config.structured_format) {
                .json => self.formatStructuredJson(
                    &result.writer,
                    level,
                    message,
                    fields,
                    metadata,
                ) catch break :blk null,
                .logfmt => self.formatStructuredLogfmt(
                    &result.writer,
                    level,
                    message,
                    fields,
                    metadata,
                ) catch break :blk null,
                .custom => self.formatStructuredCustom(
                    &result.writer,
                    level,
                    message,
                    fields,
                    metadata,
                ) catch break :blk null,
            }

            // Success! Return stack-allocated result
            break :blk result.written();
        };

        if (format_result) |stack_result| {
            // Stack allocation succeeded, copy to owned slice
            return self.allocator.dupe(u8, stack_result);
        }

        // Stack buffer too small, fall back to heap allocation
        result.deinit(); // Clean up failed stack attempt
        result = .init(self.allocator);
        errdefer result.deinit();

        switch (self.config.structured_format) {
            .json => try self.formatStructuredJson(&result.writer, level, message, fields, metadata),
            .logfmt => try self.formatStructuredLogfmt(&result.writer, level, message, fields, metadata),
            .custom => try self.formatStructuredCustom(&result.writer, level, message, fields, metadata),
        }

        return result.toOwnedSlice();
    }

    fn formatStructuredJson(
        self: *Formatter,
        writer: *std.Io.Writer,
        level: types.LogLevel,
        message: []const u8,
        fields: []const StructuredField,
        metadata: ?types.LogMetadata,
    ) !void {
        try writer.writeByte('{');
        var first = true;

        // Add timestamp if configured
        if (self.config.include_timestamp_in_structured) {
            try writer.writeAll("\"timestamp\":\"");
            try self.formatTimestamp(writer, metadata);
            try writer.writeByte('"');
            first = false;
        }

        // Add log level if configured
        if (self.config.include_level_in_structured) {
            if (!first) try writer.writeByte(',');
            try writer.writeAll("\"level\":\"");
            try self.formatLevel(writer, level);
            try writer.writeByte('"');
            first = false;
        }

        // Add message
        if (!first) try writer.writeByte(',');
        try writer.writeAll("\"msg\":\"");
        try writer.writeAll(message);
        try writer.writeByte('"');

        // Add all fields
        for (fields) |field| {
            try writer.writeAll(",\"");
            try writer.writeAll(field.name);
            try writer.writeAll("\":");
            const field_value = FieldValue{ .string = field.value };
            try field_value.format(writer);

            // Add attributes if present
            if (field.attributes) |attrs| {
                var it = attrs.iterator();
                while (it.next()) |entry| {
                    try writer.writeAll(",\"");
                    try writer.writeAll(field.name);
                    try writer.writeByte('_');
                    try writer.writeAll(entry.key_ptr.*);
                    try writer.writeAll("\":\"");
                    const value_slice = &[_]u8{entry.value_ptr.*};
                    const attr_value = FieldValue{ .string = value_slice };
                    try attr_value.format(writer);
                    try writer.writeByte('"');
                }
            }
        }

        try writer.writeByte('}');
    }

    fn escapeLogfmtValue(value: []const u8, writer: anytype) !void {
        // If value contains spaces, quotes, or equals signs, wrap in quotes and escape
        var needs_quotes = false;
        for (value) |c| {
            if (c == ' ' or c == '"' or c == '=' or c == '\n') {
                needs_quotes = true;
                break;
            }
        }

        if (needs_quotes) {
            try writer.writeByte('"');
            for (value) |c| {
                if (c == '"' or c == '\\') {
                    try writer.writeByte('\\');
                }
                try writer.writeByte(c);
            }
            try writer.writeByte('"');
        } else {
            try writer.writeAll(value);
        }
    }

    fn formatFieldValueLogfmt(value: FieldValue, writer: anytype) !void {
        switch (value) {
            .string => |str| try escapeLogfmtValue(str, writer),
            .integer => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .boolean => |b| try writer.print("{}", .{b}),
            .array => |arr| {
                try writer.writeByte('[');
                for (arr, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(",");
                    try formatFieldValueLogfmt(item, writer);
                }
                try writer.writeByte(']');
            },
            .object => |map| {
                try writer.writeByte('{');
                var it = map.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) try writer.writeAll(",");
                    try writer.print("{s}=", .{entry.key_ptr.*});
                    try formatFieldValueLogfmt(entry.value_ptr.*, writer);
                    first = false;
                }
                try writer.writeByte('}');
            },
            .null => try writer.writeAll("null"),
        }
    }

    // Add the logfmt formatter implementation
    fn formatStructuredLogfmt(
        self: *Formatter,
        writer: *std.Io.Writer,
        level: types.LogLevel,
        message: []const u8,
        fields: []const StructuredField,
        metadata: ?types.LogMetadata,
    ) !void {
        var first = true;

        // Add timestamp if configured
        if (self.config.include_timestamp_in_structured) {
            try writer.writeAll("timestamp=");
            try self.formatTimestamp(writer, metadata);
            if (!first) try writer.writeByte(' ');
            first = false;
        }

        // Add log level if configured
        if (self.config.include_level_in_structured) {
            if (!first) try writer.writeByte(' ');
            try writer.writeAll("level=");
            try self.formatLevel(writer, level);
            first = false;
        }

        // Add message
        if (!first) try writer.writeByte(' ');
        try writer.writeAll("msg=");
        try escapeLogfmtValue(message, writer);

        // Add all fields
        for (fields) |field| {
            try writer.writeByte(' ');
            try writer.writeAll(field.name);
            try writer.writeByte('=');
            const field_value = FieldValue{ .string = field.value };
            try formatFieldValueLogfmt(field_value, writer);

            // Add attributes if present
            if (field.attributes) |attrs| {
                var it = attrs.iterator();
                while (it.next()) |entry| {
                    try writer.writeByte(' ');
                    try writer.writeAll(field.name);
                    try writer.writeByte('_');
                    try writer.writeAll(entry.key_ptr.*);
                    try writer.writeByte('=');
                    const value_slice = &[_]u8{entry.value_ptr.*};
                    const attr_value = FieldValue{ .string = value_slice };
                    try attr_value.format(writer);
                }
            }
        }
    }

    // Add the custom formatter implementation
    fn formatStructuredCustom(
        self: *Formatter,
        writer: *std.Io.Writer,
        level: types.LogLevel,
        message: []const u8,
        fields: []const StructuredField,
        metadata: ?types.LogMetadata,
    ) !void {
        const field_sep = self.config.custom_field_separator orelse " | ";
        const kv_sep = self.config.custom_key_value_separator orelse "=";
        var first = true;

        // Add timestamp if configured
        if (self.config.include_timestamp_in_structured) {
            if (!first) try writer.writeAll(field_sep);
            try writer.writeAll("timestamp");
            try writer.writeAll(kv_sep);
            try self.formatTimestamp(writer, metadata);
            first = false;
        }

        // Add log level if configured
        if (self.config.include_level_in_structured) {
            if (!first) try writer.writeAll(field_sep);
            try writer.writeAll("level");
            try writer.writeAll(kv_sep);
            try self.formatLevel(writer, level);
            first = false;
        }

        // Add message
        if (!first) try writer.writeAll(field_sep);
        try writer.writeAll("msg");
        try writer.writeAll(kv_sep);
        try writer.writeAll(message);

        // Add all fields
        for (fields) |field| {
            try writer.writeAll(field_sep);
            try writer.writeAll(field.name);
            try writer.writeAll(kv_sep);
            const field_value = FieldValue{ .string = field.value };
            try field_value.format(writer);

            // Add attributes if present
            if (field.attributes) |attrs| {
                var it = attrs.iterator();
                while (it.next()) |entry| {
                    try writer.writeAll(field_sep);
                    try writer.writeAll(field.name);
                    try writer.writeByte('_');
                    try writer.writeAll(entry.key_ptr.*);
                    try writer.writeAll(kv_sep);
                    const value_slice = &[_]u8{entry.value_ptr.*};
                    const attr_value = FieldValue{ .string = value_slice };
                    try attr_value.format(writer);
                }
            }
        }
    }

    fn formatLevel(
        self: *Formatter,
        writer: *std.Io.Writer,
        level: types.LogLevel,
    ) !void {
        const level_str = level.toString();
        switch (self.config.level_format) {
            .upper => try writer.writeAll(level_str),
            .lower => {
                for (level_str) |c| {
                    try writer.writeByte(std.ascii.toLower(c));
                }
            },
            .short_upper => {
                const short = switch (level) {
                    .trace => "TRC",
                    .debug => "DBG",
                    .info => "INF",
                    .warn => "WRN",
                    .err => "ERR",
                    .critical => "CRT",
                };
                try writer.writeAll(short);
            },
            .short_lower => {
                const short = switch (level) {
                    .trace => "trc",
                    .debug => "dbg",
                    .info => "inf",
                    .warn => "wrn",
                    .err => "err",
                    .critical => "crt",
                };
                try writer.writeAll(short);
            },
        }
    }

    fn formatTimestamp(
        self: *Formatter,
        writer: *std.Io.Writer,
        metadata: ?types.LogMetadata,
    ) !void {
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();

        switch (self.config.timestamp_format) {
            .unix => try writer.print("{d}", .{timestamp}),
            .iso8601 => {
                // Convert unix timestamp to ISO 8601 format
                const unix_timestamp = @as(i64, @intCast(timestamp));

                // Convert to epoch seconds (assuming input is already in seconds)
                const epoch_seconds = unix_timestamp;

                // Calculate days since Unix epoch (1970-01-01)
                const epoch_day = @divFloor(epoch_seconds, 86400);
                const day_seconds = @mod(epoch_seconds, 86400);

                // Calculate year (simplified algorithm)
                // Days since 1970-01-01
                var days_remaining = epoch_day;
                var year: u32 = 1970;

                // Handle leap years properly
                while (days_remaining >= 365) {
                    const is_leap = (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
                    const year_days: i64 = if (is_leap) 366 else 365;
                    if (days_remaining >= year_days) {
                        days_remaining -= year_days;
                        year += 1;
                    } else {
                        break;
                    }
                }

                // Calculate month and day (simplified)
                const is_leap_year = (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
                const days_in_month = [_]i64{ 31, if (is_leap_year) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

                var month: u32 = 1;
                var day: u32 = @intCast(days_remaining + 1);

                for (days_in_month) |month_days| {
                    if (day > @as(u32, @intCast(month_days))) {
                        day -= @as(u32, @intCast(month_days));
                        month += 1;
                    } else {
                        break;
                    }
                }

                // Calculate time components
                const hour = @as(u8, @intCast(@divFloor(day_seconds, 3600)));
                const minute = @as(u8, @intCast(@mod(@divFloor(day_seconds, 60), 60)));
                const second = @as(u8, @intCast(@mod(day_seconds, 60)));

                try writer.print(
                    "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
                    .{ year, month, day, hour, minute, second },
                );
            },
            .custom => {
                if (self.config.custom_timestamp_format) |fmt_str| {
                    _ = fmt_str;
                    try writer.print("{d}", .{timestamp});
                } else {
                    try writer.print("{d}", .{timestamp});
                }
            },
        }
    }

    fn formatCustomPlaceholder(
        self: *Formatter,
        result: *std.Io.Writer,
        placeholder: Placeholder,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) !void {
        if (self.config.custom_handlers) |handlers| {
            const placeholder_name = self.config.template[placeholder.start + 1 .. placeholder.end - 1];
            if (handlers.get(placeholder_name)) |handler| {
                const custom_result = try handler(
                    self.allocator,
                    level,
                    message,
                    metadata,
                );
                defer self.allocator.free(custom_result);
                try result.writeAll(custom_result);
            } else {
                return FormatError.MissingHandler;
            }
        } else {
            return FormatError.MissingHandler;
        }
    }

    /// Helper function to create a custom placeholder handler
    pub fn registerCustomPlaceholder(
        self: *Formatter,
        name: []const u8,
        handler: CustomPlaceholderFn,
    ) !void {
        if (self.config.custom_handlers == null) {
            self.config.custom_handlers = std.StringHashMap(CustomPlaceholderFn).init(
                self.allocator,
            );
        }

        try self.config.custom_handlers.?.put(name, handler);
        // Re-parse placeholders to include new custom placeholder
        self.placeholder_cache.clearRetainingCapacity();
        try self.parsePlaceholders();
    }
};

/// Helper function to create a formatter with default configuration
pub fn createDefaultFormatter(allocator: std.mem.Allocator) !*Formatter {
    return Formatter.init(allocator, .{
        .template = "[{timestamp}] [{color}{level}{reset}] [{file}:{line}] {message}",
        .timestamp_format = .unix,
        .use_color = true,
    });
}

/// Example custom placeholder handler
pub fn hostnamePlaceholder(
    allocator: std.mem.Allocator,
    level: types.LogLevel,
    message: []const u8,
    metadata: ?types.LogMetadata,
) error{OutOfMemory}![]const u8 {
    _ = level;
    _ = message;
    _ = metadata;
    var buffer: [256]u8 = undefined; // Use a fixed size instead of HOST_NAME_MAX
    const hostname = std.posix.gethostname(&buffer) catch "unknown";
    return allocator.dupe(u8, hostname);
}
