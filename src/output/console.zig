const std = @import("std");
const types = @import("../core/types.zig");
const handlers = @import("handlers.zig");

pub const ConsoleConfig = struct {
    enable_colors: bool = true,
    min_level: types.LogLevel = .debug,
    use_stderr: bool = true,
    buffer_size: usize = 4096, // Default buffer size of 4KB

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

        // Write timestamp
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();
        try writer.print("[{d}] ", .{timestamp});

        // Write log level with colors if enabled
        if (self.config.enable_colors) {
            try writer.print("{s}[{s}]\x1b[0m ", .{ level.toColor(), level.toString() });
        } else {
            try writer.print("[{s}] ", .{level.toString()});
        }

        // Write message
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
            ConsoleHandler.log,
            ConsoleHandler.flush,
            ConsoleHandler.deinit,
        );
    }
};
