const std = @import("std");
const types = @import("../core/types.zig");

pub const JsonError = error{
    InvalidType,
    InvalidFormat,
    BufferTooSmall,
};

pub const JsonValue = union(enum) {
    null,
    bool: bool,
    number: f64,
    string: []const u8,
    array: []JsonValue,
    object: std.StringHashMap(JsonValue),

    pub fn deinit(self: *JsonValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .array => |array| {
                for (array) |*value| {
                    value.deinit(allocator);
                }
                allocator.free(array);
            },
            .object => |*map| {
                var it = map.iterator();
                while (it.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                map.deinit();
            },
            else => {},
        }
    }
};

pub fn serializeLogEntry(
    allocator: std.mem.Allocator,
    level: types.LogLevel,
    message: []const u8,
    metadata: ?types.LogMetadata,
) ![]u8 {
    var json_map = std.StringHashMap(JsonValue).init(allocator);
    defer {
        var it = json_map.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == .object) {
                entry.value_ptr.deinit(allocator);
            }
        }
        json_map.deinit();
    }

    // Add level
    try json_map.put("level", .{ .string = level.toString() });

    // Add message
    try json_map.put("message", .{ .string = message });

    // Add metadata if present
    if (metadata) |meta| {
        var meta_map = std.StringHashMap(JsonValue).init(allocator);
        errdefer meta_map.deinit();

        try meta_map.put("timestamp", .{ .number = @floatFromInt(meta.timestamp) });
        try meta_map.put("thread_id", .{ .number = @floatFromInt(meta.thread_id) });
        try meta_map.put("file", .{ .string = meta.file });
        try meta_map.put("line", .{ .number = @floatFromInt(meta.line) });
        try meta_map.put("function", .{ .string = meta.function });

        try json_map.put("metadata", .{ .object = meta_map });
    }

    // Serialize to string
    return try stringify(allocator, .{ .object = json_map });
}

pub fn stringify(allocator: std.mem.Allocator, value: JsonValue) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();

    try stringifyValue(value, &writer.writer);
    return writer.toOwnedSlice();
}

fn stringifyValue(value: JsonValue, writer: *std.Io.Writer) !void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .number => |n| try writer.print("{d}", .{n}),
        .string => |s| {
            try writer.writeByte('"');
            try escapeString(s, writer);
            try writer.writeByte('"');
        },
        .array => |arr| {
            try writer.writeByte('[');
            for (arr, 0..) |item, i| {
                if (i > 0) try writer.writeAll(", ");
                try stringifyValue(item, writer);
            }
            try writer.writeByte(']');
        },
        .object => |map| {
            try writer.writeByte('{');
            var it = map.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) try writer.writeAll(", ");
                first = false;
                try writer.writeByte('"');
                try writer.writeAll(entry.key_ptr.*);
                try writer.writeAll("\": ");
                try stringifyValue(entry.value_ptr.*, writer);
            }
            try writer.writeByte('}');
        },
    }
}

fn escapeString(s: []const u8, writer: *std.Io.Writer) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
}
