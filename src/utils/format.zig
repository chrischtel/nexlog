// utils/format.zig
const std = @import("std");
const types = @import("../core/types.zig");
// Need both StructuredField (uses FieldValue) and the old one if keeping formatStructuredFromStringFields
pub const StructuredField = @import("../core/types.zig").StructuredField;
pub const FieldValue = @import("../core/types.zig").FieldValue;
// Define the old type if needed for formatStructuredFromStringFields
const StructuredFieldString = struct { name: []const u8, value: []const u8, attributes: ?std.StringHashMap(u8) = null };

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

/// Error set for format operations
pub const FormatError = error{
    InvalidPlaceholder,
    InvalidFormat,
    MissingHandler,
    TimestampError,
    BufferTooSmall, // Added for JSON stringify potentially
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
        self.placeholder_cache.clearRetainingCapacity(); // Clear if re-parsing
        var i: usize = 0;
        while (i < self.config.template.len) {
            if (self.config.template[i] == '{') {
                const start = i;
                i += 1;
                var placeholder_name_end = start + 1;
                var found_end = false;
                var fmt_spec: ?[]const u8 = null;

                while (i < self.config.template.len) : (i += 1) {
                    if (self.config.template[i] == ':') {
                        placeholder_name_end = i; // Name ends before ':'
                        const format_start = i + 1;
                        while (i < self.config.template.len and self.config.template[i] != '}') : (i += 1) {}
                        if (i < self.config.template.len and self.config.template[i] == '}') {
                            fmt_spec = self.config.template[format_start..i];
                            found_end = true;
                            break;
                        } else {
                            // Unterminated format specifier
                            return FormatError.InvalidPlaceholder;
                        }
                    } else if (self.config.template[i] == '}') {
                        placeholder_name_end = i; // Name ends before '}'
                        found_end = true;
                        break;
                    }
                }

                if (!found_end) {
                    return FormatError.InvalidPlaceholder;
                }

                const placeholder_name = self.config.template[start + 1 .. placeholder_name_end];
                const placeholder_type = self.getPlaceholderType(placeholder_name) catch |err| {
                    std.debug.print("Invalid placeholder: {s}\n", .{placeholder_name});
                    return err;
                };

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
        if (std.mem.eql(u8, name, "request_id")) return .request_id;
        if (std.mem.eql(u8, name, "correlation_id")) return .correlation_id;
        if (std.mem.eql(u8, name, "trace_id")) return .trace_id;
        if (std.mem.eql(u8, name, "span_id")) return .span_id;
        if (std.mem.eql(u8, name, "user_id")) return .user_id;
        if (std.mem.eql(u8, name, "session_id")) return .session_id;
        if (std.mem.eql(u8, name, "operation")) return .operation;
        if (std.mem.eql(u8, name, "component")) return .component;

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
        const default_structured_stack_buffer_size = 2048; // Or another reasonable fixed size
        var stack_buffer: [default_structured_stack_buffer_size]u8 = undefined;

        // formatWithBuffer will handle falling back to heap if this is too small
        return self.formatWithBuffer(&stack_buffer, level, message, metadata);
    }

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

        const format_result = blk: {
            var last_pos: usize = 0;
            for (self.placeholder_cache.items) |placeholder| {
                result.writer.writeAll(self.config.template[last_pos..placeholder.start]) catch break :blk null;
                self.formatPlaceholder(&result.writer, placeholder, level, message, metadata) catch break :blk null;
                last_pos = placeholder.end;
            }
            result.writer.writeAll(self.config.template[last_pos..]) catch break :blk null;
            break :blk result.written();
        };

        if (format_result) |stack_result| return self.allocator.dupe(u8, stack_result);

        result.deinit(); // Clean up failed stack attempt
        result = .init(self.allocator);
        errdefer result.deinit();

        var last_pos: usize = 0;
        for (self.placeholder_cache.items) |placeholder| {
            try result.writer.writeAll(self.config.template[last_pos..placeholder.start]);
            try self.formatPlaceholder(&result.writer, placeholder, level, message, metadata);
            last_pos = placeholder.end;
        }
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

    fn formatContextField(
        self: *Formatter,
        writer: *std.Io.Writer,
        metadata: ?types.LogMetadata,
        field_name: []const u8,
    ) !void {
        _ = self;
        const default_char = '-';
        if (metadata) |m| {
            if (m.context) |context| {
                const field_value = if (std.mem.eql(u8, field_name, "request_id")) context.request_id else if (std.mem.eql(u8, field_name, "correlation_id")) context.correlation_id else if (std.mem.eql(u8, field_name, "trace_id")) context.trace_id else if (std.mem.eql(u8, field_name, "span_id")) context.span_id else if (std.mem.eql(u8, field_name, "user_id")) context.user_id else if (std.mem.eql(u8, field_name, "session_id")) context.session_id else if (std.mem.eql(u8, field_name, "operation")) context.operation else if (std.mem.eql(u8, field_name, "component")) context.function else null;

                if (field_value) |value| {
                    try writer.writeAll(value);
                } else {
                    try writer.writeByte(default_char);
                }
            } else {
                try writer.writeByte(default_char);
            }
        } else {
            try writer.writeByte(default_char);
        }
    }

    // --- START STRUCTURED FORMATTING SECTION ---

    /// (Optional: Kept for backward compatibility if needed)
    /// Formats structured data where fields' values are already strings.
    pub fn formatStructuredFromStringFields(
        self: *Formatter,
        level: types.LogLevel,
        message: []const u8,
        fields: []const StructuredFieldString, // Uses the old string-based type
        metadata: ?types.LogMetadata,
    ) ![]const u8 {
        // Convert string fields back to FieldValue for the new function
        // Note: This assumes all original values were strings.
        var temp_fields = std.ArrayList(StructuredField).init(self.allocator);
        defer temp_fields.deinit();
        for (fields) |sf_str| {
            try temp_fields.append(.{ .name = sf_str.name, .value = .{ .string = sf_str.value } });
            // Attributes might need conversion too if used
        }
        // Delegate to the primary structured formatting function
        return self.formatStructuredWithFields(level, message, temp_fields.items, metadata);
    }

    /// Formats structured data with typed FieldValues. Allocates memory for the result.
    pub fn formatStructuredWithFields(
        self: *Formatter,
        level: types.LogLevel,
        message: []const u8,
        fields: types.StructuredData, // Uses []const StructuredField with FieldValue
        metadata: ?types.LogMetadata,
    ) ![]const u8 {
        // Use stack buffer / heap fallback logic
        const default_structured_stack_buffer_size = 2048; // Or another reasonable fixed size
        var stack_buffer: [default_structured_stack_buffer_size]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&stack_buffer);
        const stack_allocator = fba.allocator();
        var result: std.Io.Writer.Allocating = .init(stack_allocator);

        const format_result = blk: {
            switch (self.config.structured_format) {
                .json => self.formatFieldsJson(&result.writer, level, message, fields, metadata) catch break :blk null,
                .logfmt => self.formatFieldsLogfmt(&result.writer, level, message, fields, metadata) catch break :blk null,
                .custom => self.formatFieldsCustom(&result.writer, level, message, fields, metadata) catch break :blk null,
            }
            break :blk result.written();
        };

        if (format_result) |stack_res| return self.allocator.dupe(u8, stack_res);

        // Fallback to heap
        result.deinit();
        result = .init(self.allocator);
        errdefer result.deinit();
        switch (self.config.structured_format) {
            .json => try self.formatFieldsJson(&result.writer, level, message, fields, metadata),
            .logfmt => try self.formatFieldsLogfmt(&result.writer, level, message, fields, metadata),
            .custom => try self.formatFieldsCustom(&result.writer, level, message, fields, metadata),
        }
        return result.toOwnedSlice();
    }

    /// Format structured data into JSON format.
    fn formatFieldsJson(
        self: *Formatter,
        writer: *std.Io.Writer,
        level: types.LogLevel,
        message: []const u8,
        fields: types.StructuredData,
        metadata: ?types.LogMetadata,
    ) !void {
        try writer.writeByte('{');
        var first = true;

        // Helper to add comma
        if (!first) try writer.writeByte(',');
        first = false;

        // Add timestamp if configured
        if (self.config.include_timestamp_in_structured) {
            if (!first) try writer.writeByte(',');
            first = false;
            try writer.writeAll("\"timestamp\":");
            try self.formatTimestampJsonValue(writer, metadata);
        }

        // Add log level if configured
        if (self.config.include_level_in_structured) {
            if (!first) try writer.writeByte(',');
            first = false;
            try writer.writeAll("\"level\":\"");
            try self.formatLevel(writer, level);
            try writer.writeByte('"');
        }

        // Add message
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeAll("\"msg\":");
        try self.formatFieldValueJson(writer, .{ .string = message });

        // Add all fields
        for (fields) |field| {
            if (!first) try writer.writeByte(',');
            first = false;
            try writer.writeByte('"');
            // TODO: Potentially escape field.name if it can contain quotes/control chars
            try writer.writeAll(field.name);
            try writer.writeAll("\":");
            try self.formatFieldValueJson(writer, field.value);
            // TODO: Handle attributes for JSON output
        }

        try writer.writeByte('}');
    }

    /// Format a FieldValue into its JSON representation.
    fn formatFieldValueJson(self: *Formatter, writer: *std.Io.Writer, value: types.FieldValue) !void {
        switch (value) {
            .string => |s| {
                var jsonifier = std.json.Stringify{
                    .writer = writer,
                    .options = .{},
                };

                try jsonifier.write(s);
            },
            .integer => |i| try writer.print("{d}", .{i}),
            .float => |f| {
                if (std.math.isInf(f) or std.math.isNan(f)) {
                    try writer.writeAll("null");
                } else {
                    // Use std.fmt which should handle floats correctly for JSON
                    try writer.print("{d}", .{f});
                }
            },
            .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
            .null => try writer.writeAll("null"),
            // --- IMPLEMENTED ARRAY ---
            .array => |arr| {
                try writer.writeByte('[');
                for (arr, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(","); // Add comma before subsequent items
                    // Recursively call the function for each item
                    try self.formatFieldValueJson(writer, item);
                }
                try writer.writeByte(']');
            },
            .object => |map| {
                var jsonifier = std.json.Stringify{
                    .writer = writer,
                    .options = .{},
                };

                try jsonifier.beginObject();

                var it = map.iterator();
                while (it.next()) |entry| {
                    try jsonifier.objectField(entry.key_ptr.*);
                    try self.formatFieldValueJson(jsonifier.writer, entry.value_ptr.*);
                }

                try jsonifier.endObject();
            },
        }
    }

    /// Format timestamp specifically for JSON (number or string).
    fn formatTimestampJsonValue(self: *Formatter, writer: *std.Io.Writer, metadata: ?types.LogMetadata) !void {
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();
        switch (self.config.timestamp_format) {
            .unix => try writer.print("{d}", .{timestamp}), // Number
            .iso8601, .custom => { // String
                try writer.writeByte('"');
                try self.formatTimestamp(writer, metadata); // This writes the string content
                try writer.writeByte('"');
            },
        }
    }

    /// Format structured data into logfmt format.
    fn formatFieldsLogfmt(
        self: *Formatter,
        writer: *std.Io.Writer,
        level: types.LogLevel,
        message: []const u8,
        fields: types.StructuredData,
        metadata: ?types.LogMetadata,
    ) !void {
        var first = true;

        // Helper to add space
        if (!first) try writer.writeByte(' ');
        first = false;

        // Add timestamp if configured
        if (self.config.include_timestamp_in_structured) {
            if (!first) try writer.writeByte(' ');
            first = false;
            try writer.writeAll("timestamp=");
            try self.formatTimestampLogfmtValue(writer, metadata);
        }

        // Add log level if configured
        if (self.config.include_level_in_structured) {
            if (!first) try writer.writeByte(' ');
            first = false;
            try writer.writeAll("level=");
            try self.formatLevel(writer, level);
        }

        // Add message
        if (!first) try writer.writeByte(' ');
        first = false;
        try writer.writeAll("msg=");
        try self.formatFieldValueLogfmt(writer, .{ .string = message });

        // Add all fields
        for (fields) |field| {
            if (!first) try writer.writeByte(' ');
            first = false;
            // TODO: Potentially escape field.name if it contains spaces/=
            try writer.writeAll(field.name);
            try writer.writeByte('=');
            try self.formatFieldValueLogfmt(writer, field.value);
            // TODO: Handle attributes for logfmt output
        }
    }

    /// Format a FieldValue into its logfmt representation (quoting/escaping strings).
    fn formatFieldValueLogfmt(self: *Formatter, writer: *std.Io.Writer, value: types.FieldValue) !void {
        switch (value) {
            .string => |s| try self.escapeLogfmtValue(s, writer),
            .integer => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
            .null => try writer.writeAll("null"), // Consider ""?
            // Optional types not yet handled
            .array => |arr| {
                try writer.writeAll("[");
                var first = true;
                for (arr) |elem| {
                    if (!first) try writer.writeAll(", ");
                    first = false;
                    try self.formatFieldValueLogfmt(writer, elem);
                }
                try writer.writeAll("]");
            },
            .object => |obj| {
                try writer.writeAll("{");
                var it = obj.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) try writer.writeAll(", ");
                    first = false;
                    try writer.print("{s}=", .{entry.key_ptr.*});
                    try self.formatFieldValueLogfmt(writer, entry.value_ptr.*);
                }
                try writer.writeAll("}");
            },
        }
    }

    /// Format timestamp specifically for logfmt (number or potentially quoted string).
    fn formatTimestampLogfmtValue(self: *Formatter, writer: *std.Io.Writer, metadata: ?types.LogMetadata) !void {
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();

        switch (self.config.timestamp_format) {
            .unix => try writer.print("{d}", .{timestamp}), // number
            .iso8601, .custom => { // string - needs potential quoting
                var time_buf: [64]u8 = undefined;
                var inner_writer = std.Io.Writer.fixed(&time_buf);

                const before = inner_writer.end;
                try self.formatTimestamp(&inner_writer, metadata);
                const written_slice = time_buf[0 .. inner_writer.end - before];

                try self.escapeLogfmtValue(written_slice, writer);
            },
        }
    }
    /// Format structured data into a custom key-value format.
    fn formatFieldsCustom(
        self: *Formatter,
        writer: *std.Io.Writer,
        level: types.LogLevel,
        message: []const u8,
        fields: types.StructuredData,
        metadata: ?types.LogMetadata,
    ) !void {
        const field_sep = self.config.custom_field_separator orelse " | ";
        const kv_sep = self.config.custom_key_value_separator orelse "=";
        var first = true;

        // Helper to add separator
        if (!first) try writer.writeAll(field_sep);
        first = false;

        // Add timestamp if configured
        if (self.config.include_timestamp_in_structured) {
            if (!first) try writer.writeAll(field_sep);
            first = false;
            try writer.writeAll("timestamp");
            try writer.writeAll(kv_sep);
            try self.formatTimestampLogfmtValue(writer, metadata); // Reuse logfmt value formatting
        }

        // Add log level if configured
        if (self.config.include_level_in_structured) {
            if (!first) try writer.writeAll(field_sep);
            first = false;
            try writer.writeAll("level");
            try writer.writeAll(kv_sep);
            try self.formatLevel(writer, level);
        }

        // Add message
        if (!first) try writer.writeAll(field_sep);
        first = false;
        try writer.writeAll("msg");
        try writer.writeAll(kv_sep);
        try self.formatFieldValueLogfmt(writer, .{ .string = message }); // Reuse logfmt value formatting

        // Add all fields
        for (fields) |field| {
            if (!first) try writer.writeAll(field_sep);
            first = false;
            try writer.writeAll(field.name); // Assume simple name
            try writer.writeAll(kv_sep);
            try self.formatFieldValueLogfmt(writer, field.value); // Reuse logfmt value formatting
            // TODO: Handle attributes for custom output
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
                for (level_str) |c| try writer.writeByte(std.ascii.toLower(c));
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
                // Check if std.time.format is available (Zig 0.11+)
                if (@hasDecl(std.time, "format")) {
                    var time_buf: [30]u8 = undefined; // Buffer for ISO 8601
                    const formatted_time = try std.time.format(timestamp, .iso8601, &time_buf);
                    try writer.writeAll(formatted_time);
                } else {
                    // Fallback to manual formatting for older Zig versions
                    try self.formatTimestampIso8601Manual(writer, timestamp);
                }
            },
            .custom => {
                if (self.config.custom_timestamp_format) |fmt_str| {
                    // Custom formatting logic would go here if std.time.format isn't used/available
                    // For now, just print unix as fallback
                    _ = fmt_str;
                    try writer.print("{d}", .{timestamp}); // Fallback
                } else {
                    try writer.print("{d}", .{timestamp}); // Fallback
                }
            },
        }
    }

    // Manual ISO8601 formatter (fallback for older Zig)
    fn formatTimestampIso8601Manual(self: *Formatter, writer: *std.Io.Writer, unix_timestamp: i64) !void {
        _ = self;
        const epoch_seconds = unix_timestamp;
        const epoch_day = @divFloor(epoch_seconds, 86400);
        const day_seconds = @mod(epoch_seconds, 86400);

        var days_remaining = epoch_day;
        var year: u32 = 1970;
        while (days_remaining >= 365) {
            const is_leap = (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
            const year_days: i64 = if (is_leap) 366 else 365;
            if (days_remaining >= year_days) {
                days_remaining -= year_days;
                year += 1;
            } else break;
        }

        const is_leap_year = (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
        const days_in_month = [_]i64{ 31, if (is_leap_year) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var month: u32 = 1;
        var day: u32 = @intCast(days_remaining + 1);
        for (days_in_month) |month_days| {
            if (day > @as(u32, @intCast(month_days))) {
                day -= @as(u32, @intCast(month_days));
                month += 1;
            } else break;
        }

        const hour = @as(u8, @intCast(@divFloor(day_seconds, 3600)));
        const minute = @as(u8, @intCast(@mod(@divFloor(day_seconds, 60), 60)));
        const second = @as(u8, @intCast(@mod(day_seconds, 60)));

        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{ year, month, day, hour, minute, second });
    }

    fn formatCustomPlaceholder(
        self: *Formatter,
        writer: *std.Io.Writer,
        placeholder: Placeholder,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) !void {
        if (self.config.custom_handlers) |handlers| {
            // Need to extract the name without format specifier if present
            const name_end = if (placeholder.format) |fmt|
                placeholder.end - fmt.len - 2 // Adjust for ':' and '}'
            else
                placeholder.end - 1; // Adjust for '}'
            const placeholder_name = self.config.template[placeholder.start + 1 .. name_end];

            if (handlers.get(placeholder_name)) |handler| {
                const custom_result = try handler(self.allocator, level, message, metadata);
                defer self.allocator.free(custom_result);
                try writer.writeAll(custom_result);
            } else {
                try writer.print("{{ERR:Unknown '{s}'}}", .{placeholder_name}); // Output error inline
                // return FormatError.MissingHandler; // Or return error
            }
        } else {
            try writer.print("{{ERR:No Custom Handlers}}", .{});
            // return FormatError.MissingHandler; // Or return error
        }
    }

    /// Helper function to escape strings for logfmt output
    fn escapeLogfmtValue(self: *Formatter, value: []const u8, writer: *std.Io.Writer) !void {
        _ = self;
        var needs_quotes = false;
        for (value) |c| {
            if (c <= ' ' or c == '"' or c == '=' or c == '`') { // Include backtick, control chars
                needs_quotes = true;
                break;
            }
        }

        if (needs_quotes) {
            try writer.writeByte('"');
            for (value) |c| {
                switch (c) {
                    '"' => try writer.writeAll("\\\""),
                    '\\' => try writer.writeAll("\\\\"),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    '\t' => try writer.writeAll("\\t"),
                    else => {
                        // Escape other control characters if necessary
                        if (c < ' ') {
                            try writer.print("\\u{X:0>4}", .{@as(u16, c)});
                        } else {
                            try writer.writeByte(c);
                        }
                    },
                }
            }
            try writer.writeByte('"');
        } else {
            try writer.writeAll(value);
        }
    }

    /// Register a custom placeholder handler
    pub fn registerCustomPlaceholder(
        self: *Formatter,
        name: []const u8,
        handler: CustomPlaceholderFn,
    ) !void {
        if (self.config.custom_handlers == null) {
            self.config.custom_handlers = std.StringHashMap(CustomPlaceholderFn).init(self.allocator);
        }
        // Should copy the name for the map key
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        try self.config.custom_handlers.?.put(name_copy, handler);

        // Re-parse placeholders to recognize the new custom one
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
    _ = metadata; // Keep parameters for signature match
    var buffer: [256]u8 = undefined;
    const hostname = std.posix.gethostname(&buffer) catch "unknown";
    return allocator.dupe(u8, hostname);
}
