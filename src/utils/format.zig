// utils/format.zig
const std = @import("std");
const types = @import("../core/types.zig");

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
            .placeholder_cache = std.ArrayList(Placeholder).init(allocator),
        };
        // Parse template once during initialization
        try self.parsePlaceholders();
        return self;
    }

    pub fn deinit(self: *Formatter) void {
        self.placeholder_cache.deinit();
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

                try self.placeholder_cache.append(.{
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
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var last_pos: usize = 0;

        for (self.placeholder_cache.items) |placeholder| {
            // Add text before placeholder
            try result.appendSlice(self.config.template[last_pos..placeholder.start]);

            // Format placeholder
            try self.formatPlaceholder(
                &result,
                placeholder,
                level,
                message,
                metadata,
            );

            last_pos = placeholder.end;
        }

        // Add remaining text after last placeholder
        try result.appendSlice(self.config.template[last_pos..]);

        return result.toOwnedSlice();
    }

    fn formatPlaceholder(
        self: *Formatter,
        result: *std.ArrayList(u8),
        placeholder: Placeholder,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) !void {
        switch (placeholder.type) {
            .level => try self.formatLevel(result, level),
            .message => try result.appendSlice(message),
            .timestamp => try self.formatTimestamp(result, metadata),
            .thread => if (metadata) |m| try std.fmt.format(result.writer(), "{d}", .{m.thread_id}),
            .file => if (metadata) |m| try result.appendSlice(m.file),
            .line => if (metadata) |m| try std.fmt.format(result.writer(), "{d}", .{m.line}),
            .function => if (metadata) |m| try result.appendSlice(m.function),
            .color => if (self.config.use_color) try result.appendSlice(level.toColor()),
            .reset => if (self.config.use_color) try result.appendSlice("\x1b[0m"),
            .custom => try self.formatCustomPlaceholder(result, placeholder, level, message, metadata),
        }
    }
    // utils/format.zig (continued)

    fn formatLevel(
        self: *Formatter,
        result: *std.ArrayList(u8),
        level: types.LogLevel,
    ) !void {
        const level_str = level.toString();
        switch (self.config.level_format) {
            .upper => try result.appendSlice(level_str),
            .lower => {
                for (level_str) |c| {
                    try result.append(std.ascii.toLower(c));
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
                try result.appendSlice(short);
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
                try result.appendSlice(short);
            },
        }
    }

    fn formatTimestamp(
        self: *Formatter,
        result: *std.ArrayList(u8),
        metadata: ?types.LogMetadata,
    ) !void {
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();

        switch (self.config.timestamp_format) {
            .unix => try std.fmt.format(result.writer(), "{d}", .{timestamp}),
            .iso8601 => {
                // Convert unix timestamp to ISO 8601 format
                const unix_timestamp = @as(i64, @intCast(timestamp));
                const epoch_seconds = @divFloor(unix_timestamp, 1000);
                const ms = @mod(unix_timestamp, 1000);

                // Convert to broken down time
                var timer = try std.time.Timer.start();
                const epoch_day = @divFloor(epoch_seconds, 86400);
                const day_seconds = @mod(epoch_seconds, 86400);

                // Use integer division instead of floating point
                // 146097 days = 400 years
                const year_day = @as(u16, @intCast(@divFloor(epoch_day + 719468, 146097) * 400));
                const year = 1970 + year_day;

                const hour = @as(u8, @intCast(@divFloor(day_seconds, 3600)));
                const minute = @as(u8, @intCast(@mod(@divFloor(day_seconds, 60), 60)));
                const second = @as(u8, @intCast(@mod(day_seconds, 60)));

                try std.fmt.format(
                    result.writer(),
                    "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z",
                    .{ year, timer.read(), timer.lap(), hour, minute, second, ms },
                );
            },
            .custom => {
                if (self.config.custom_timestamp_format) |fmt_str| {
                    _ = fmt_str;
                    try std.fmt.format(result.writer(), "{d}", .{timestamp});
                } else {
                    try std.fmt.format(result.writer(), "{d}", .{timestamp});
                }
            },
        }
    }

    fn formatCustomPlaceholder(
        self: *Formatter,
        result: *std.ArrayList(u8),
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
                try result.appendSlice(custom_result);
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
    var buffer: [std.os.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.os.gethostname(&buffer);
    return allocator.dupe(u8, hostname);
}
