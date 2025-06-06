const std = @import("std");
const types = @import("../core/types.zig");
const handlers = @import("handlers.zig");

pub const ConsoleConfig = struct {
    enable_colors: bool = true,
    min_level: types.LogLevel = .debug,
    use_stderr: bool = true,
    buffer_size: usize = 4096,

    show_source_location: bool = true,
    show_function: bool = false,
    show_thread_id: bool = false,
};

pub const ConsoleHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: ConsoleConfig,

    pub fn init(allocator: std.mem.Allocator, config: ConsoleConfig) !*Self {
        const handler = try allocator.create(Self);
        handler.* = .{
            .allocator = allocator,
            .config = config,
        };
        return handler;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn log(
        self: *Self,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) !void {
        if (@intFromEnum(level) < @intFromEnum(self.config.min_level)) {
            return;
        }

        const writer = if (self.config.use_stderr)
            std.io.getStdErr().writer()
        else
            std.io.getStdOut().writer();

        // Display more metadata information according to configuration
        if (self.config.enable_colors) {
            try writer.print("{s}", .{level.toColor()});
        }

        // Display standard timestamp & level info
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();
        try writer.print("[{d}] ", .{timestamp});

        // Print level
        if (self.config.enable_colors) {
            try writer.print("[{s}]", .{level.toString()});
            try writer.print("\x1b[0m ", .{}); // Reset color
        } else {
            try writer.print("[{s}] ", .{level.toString()});
        }

        // Include file and line information if available
        if (metadata != null and self.config.show_source_location) {
            const file = metadata.?.file;
            // Get just the filename without the path
            const filename = std.fs.path.basename(file);
            try writer.print("[{s}:{d}] ", .{ filename, metadata.?.line });
        }

        // Include function name if available
        if (metadata != null and self.config.show_function) {
            try writer.print("[{s}] ", .{metadata.?.function});
        }

        // Include thread ID if available
        if (metadata != null and self.config.show_thread_id) {
            try writer.print("[tid:{d}] ", .{metadata.?.thread_id});
        }

        // Write the actual message
        try writer.print("{s}\n", .{message});
    }

    pub fn flush(self: *Self) !void {
        // Console output is immediately flushed, so this is a no-op
        _ = self;
    }

    /// Convert to generic LogHandler interface
    pub fn toLogHandler(self: *Self) handlers.LogHandler {
        return handlers.LogHandler.init(
            self,
            .console,
            ConsoleHandler.log,
            ConsoleHandler.writeFormattedLog,
            ConsoleHandler.flush,
            ConsoleHandler.deinit,
        );
    }

    pub fn writeFormattedLog(self: *Self, formatted_message: []const u8) !void {
        // No level check needed here since the message is already formatted
        const writer = if (self.config.use_stderr)
            std.io.getStdErr().writer()
        else
            std.io.getStdOut().writer();

        // Just write the already formatted message
        try writer.print("{s}\n", .{formatted_message});
    }
};
