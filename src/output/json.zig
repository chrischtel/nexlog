const std = @import("std");
const types = @import("../core/types.zig");
const handlers = @import("handlers.zig");
const json = @import("../utils/json.zig");
const errors = @import("../core/errors.zig");

pub const JsonHandlerConfig = struct {
    min_level: types.LogLevel = .debug,
    pretty_print: bool = false,
    buffer_size: usize = 4096,
    output_file: ?[]const u8 = null,
};

pub const JsonHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: JsonHandlerConfig,
    file: ?std.fs.File,
    has_written: bool,
    is_initialized: bool, // Add this to track initialization state

    pub fn init(allocator: std.mem.Allocator, config: JsonHandlerConfig) errors.Error!*Self {
        var handler = try allocator.create(Self);
        errdefer allocator.destroy(handler);

        handler.* = .{
            .allocator = allocator,
            .config = config,
            .file = null,
            .has_written = false,
            .is_initialized = false,
        };

        if (config.output_file) |path| {
            const file = try std.fs.createFileAbsolute(path, .{
                .read = true,
                .truncate = true,
            });
            try file.writeAll("[\n");
            handler.file = file;
        }

        handler.is_initialized = true;
        return handler;
    }

    pub fn deinit(self: *Self) void {
        if (!self.is_initialized) return;

        if (self.file) |file| {
            if (self.has_written) {
                file.writeAll("\n]") catch {};
            } else {
                file.writeAll("[]") catch {};
            }
            // Store the allocator before we potentially invalidate self
            const allocator = self.allocator;
            self.file = null;
            self.is_initialized = false;
            allocator.destroy(self);
        } else {
            const allocator = self.allocator;
            self.is_initialized = false;
            allocator.destroy(self);
        }
    }

    pub fn log(
        self: *Self,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) errors.Error!void {
        if (!self.is_initialized) return error.NotInitialized;
        if (@intFromEnum(level) < @intFromEnum(self.config.min_level)) {
            return;
        }

        const json_str = try json.serializeLogEntry(
            self.allocator,
            level,
            message,
            metadata,
        );
        defer self.allocator.free(json_str);

        if (self.file) |*file| {
            if (self.has_written) {
                try file.writeAll(",\n");
            }
            try file.writeAll(json_str);
            self.has_written = true;
        } else {
            try std.io.getStdOut().writer().print("{s}\n", .{json_str});
        }
    }

    pub fn flush(self: *Self) errors.Error!void {
        if (!self.is_initialized) return error.NotInitialized;
        if (self.file) |*file| {
            try file.sync();
        }
    }

    pub fn toLogHandler(self: *Self) handlers.LogHandler {
        return handlers.LogHandler.init(
            self,
            JsonHandler.log,
            JsonHandler.flush,
            JsonHandler.deinit,
        );
    }
};
