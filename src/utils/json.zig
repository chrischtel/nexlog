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
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try stringifyValue(value, &list);
    return list.toOwnedSlice();
}

fn stringifyValue(value: JsonValue, list: *std.ArrayList(u8)) !void {
    switch (value) {
        .null => try list.appendSlice("null"),
        .bool => |b| try list.appendSlice(if (b) "true" else "false"),
        .number => |n| try std.fmt.format(list.writer(), "{d}", .{n}),
        .string => |s| {
            try list.append('"');
            try escapeString(s, list);
            try list.append('"');
        },
        .array => |arr| {
            try list.append('[');
            for (arr, 0..) |item, i| {
                if (i > 0) try list.appendSlice(", ");
                try stringifyValue(item, list);
            }
            try list.append(']');
        },
        .object => |map| {
            try list.append('{');
            var it = map.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) try list.appendSlice(", ");
                first = false;
                try list.append('"');
                try list.appendSlice(entry.key_ptr.*);
                try list.appendSlice("\": ");
                try stringifyValue(entry.value_ptr.*, list);
            }
            try list.append('}');
        },
    }
}

fn escapeString(s: []const u8, list: *std.ArrayList(u8)) !void {
    for (s) |c| {
        switch (c) {
            '"' => try list.appendSlice("\\\""),
            '\\' => try list.appendSlice("\\\\"),
            '\n' => try list.appendSlice("\\n"),
            '\r' => try list.appendSlice("\\r"),
            '\t' => try list.appendSlice("\\t"),
            else => try list.append(c),
        }
    }
}
