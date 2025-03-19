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
    is_initialized: bool,

    pub fn init(allocator: std.mem.Allocator, config: JsonHandlerConfig) errors.Error!*Self {
        // Allocate the handler first
        var handler = try allocator.create(Self);
        errdefer allocator.destroy(handler);

        // Initialize with safe defaults
        handler.* = .{
            .allocator = allocator,
            .config = config,
            .file = null,
            .has_written = false,
            .is_initialized = false,
        };

        // Handle file creation separately
        if (config.output_file) |path| {
            handler.file = std.fs.createFileAbsolute(path, .{
                .read = true,
                .truncate = true,
            }) catch |err| {
                allocator.destroy(handler);
                return err;
            };

            // Write initial bracket
            handler.file.?.writeAll("[\n") catch |err| {
                handler.file.?.close();
                allocator.destroy(handler);
                return err;
            };
        }

        handler.is_initialized = true;
        return handler;
    }

    pub fn deinit(self: *Self) void {
        // Guard against double-free
        if (!self.is_initialized) return;

        // Create local copies of needed values
        const was_written = self.has_written;
        const allocator = self.allocator;

        // Mark as not initialized first
        self.is_initialized = false;

        // Handle file cleanup
        if (self.file) |file| {
            // Write closing content
            if (was_written) {
                file.writeAll("\n]") catch {};
            } else {
                file.writeAll("[]") catch {};
            }

            // Close the file
            file.close();
        }

        // Clear all fields before destruction
        self.* = undefined;

        // Finally destroy the handler
        allocator.destroy(self);
    }

    pub fn log(
        self: *Self,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) errors.Error!void {
        if (!self.is_initialized) return error.NotInitialized;

        // Early return for filtered levels
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
            // Add comma if not first entry
            if (self.has_written) {
                try file.writeAll(",\n");
            }
            try file.writeAll(json_str);
            self.has_written = true;
        } else {
            try std.io.getStdOut().writer().print("{s}\n", .{json_str});
        }
    }

    pub fn writeFormattedLog(
        self: *Self,
        formatted_message: []const u8,
    ) errors.Error!void {
        if (!self.is_initialized) return error.NotInitialized;

        // For the JSON handler, we handle formatted messages by writing them directly
        // But we need to ensure the JSON structure is maintained

        if (self.file) |*file| {
            // Add comma if not first entry
            if (self.has_written) {
                try file.writeAll(",\n");
            }

            // Since we don't know the structure of the formatted message,
            // we'll wrap it in a simplified JSON object
            const buf = try self.allocator.alloc(u8, formatted_message.len + 40);
            defer self.allocator.free(buf);

            const json_wrapper = std.fmt.bufPrint(
                buf,
                "{{ \"message\": {s} }}",
                .{std.fmt.fmtSliceEscapeUpper(formatted_message)},
            ) catch |err| {
                // Fallback to direct writing if formatting fails
                try file.writeAll(formatted_message);
                self.has_written = true;
                return err;
            };

            try file.writeAll(json_wrapper);
            self.has_written = true;
        } else {
            try std.io.getStdOut().writer().print("{s}\n", .{formatted_message});
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
            JsonHandler.writeFormattedLog,
            JsonHandler.flush,
            JsonHandler.deinit,
        );
    }
};
