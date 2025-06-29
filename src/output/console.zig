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

    /// Use fast path optimization for high-performance logging
    /// Disables some formatting features but significantly faster
    fast_mode: bool = false,
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

        // Ultra-fast mode: minimal formatting for maximum throughput
        if (self.config.fast_mode) {
            const final_writer = if (self.config.use_stderr)
                std.io.getStdErr().writer()
            else
                std.io.getStdOut().writer();

            const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();
            try final_writer.print("[{d}] {s}\n", .{ timestamp, message });
            return;
        }

        // Use stack buffer for common case to avoid allocation
        var buffer: [2048]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const temp_allocator = fba.allocator();

        var output = std.ArrayList(u8).init(temp_allocator);
        const writer = output.writer();

        // Pre-calculate timestamp once
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();

        // Fast path: Simple format without metadata
        if (metadata == null or (!self.config.show_source_location and !self.config.show_function and !self.config.show_thread_id)) {
            if (self.config.enable_colors) {
                try writer.print("{s}[{d}] [{s}]\x1b[0m {s}\n", .{
                    level.toColor(),
                    timestamp,
                    level.toString(),
                    message,
                });
            } else {
                try writer.print("[{d}] [{s}] {s}\n", .{
                    timestamp,
                    level.toString(),
                    message,
                });
            }
        } else {
            // Full format with metadata
            if (self.config.enable_colors) {
                try writer.print("{s}[{d}] [{s}]\x1b[0m", .{
                    level.toColor(),
                    timestamp,
                    level.toString(),
                });
            } else {
                try writer.print("[{d}] [{s}]", .{
                    timestamp,
                    level.toString(),
                });
            }

            // Add optional metadata components in one pass
            if (metadata) |m| {
                if (self.config.show_source_location) {
                    // Cache basename to avoid repeated path parsing
                    const filename = std.fs.path.basename(m.file);
                    try writer.print(" [{s}:{d}]", .{ filename, m.line });
                }

                if (self.config.show_function) {
                    try writer.print(" [{s}]", .{m.function});
                }

                if (self.config.show_thread_id) {
                    try writer.print(" [tid:{d}]", .{m.thread_id});
                }
            }

            try writer.print(" {s}\n", .{message});
        }

        // Single write to output stream
        const final_writer = if (self.config.use_stderr)
            std.io.getStdErr().writer()
        else
            std.io.getStdOut().writer();

        try final_writer.writeAll(output.items);
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
