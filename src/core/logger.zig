const std = @import("std");
const types = @import("types.zig");
const cfg = @import("config.zig");
const errors = @import("errors.zig");
const handlers = @import("../output/handlers.zig");

const console = @import("../output/console.zig");
const file = @import("../output/file.zig");
const network = @import("../output/network.zig");
const format = @import("../utils/format.zig");
pub const Logger = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: cfg.LogConfig,
    mutex: std.Thread.Mutex,
    handlers: std.ArrayList(handlers.LogHandler),
    formatter: ?*format.Formatter, // Add formatter

    pub fn init(allocator: std.mem.Allocator, config: cfg.LogConfig) !*Self {
        var logger = try allocator.create(Self);

        const formatter = if (config.format_config) |fmt_config|
            try format.Formatter.init(allocator, fmt_config)
        else
            try format.createDefaultFormatter(allocator);

        // Initialize base logger
        logger.* = .{
            .allocator = allocator,
            .config = config,
            .mutex = std.Thread.Mutex{},
            .handlers = std.ArrayList(handlers.LogHandler).init(allocator),
            .formatter = formatter,
        };

        // Initialize console handler by default
        if (config.enable_console) {
            const console_config = console.ConsoleConfig{
                .use_stderr = true,
                .enable_colors = config.enable_colors,
                .buffer_size = config.buffer_size,
                .min_level = config.min_level,
            };
            var console_handler = try console.ConsoleHandler.init(allocator, console_config);
            try logger.addHandler(console_handler.toLogHandler());
        }

        // Initialize file handler if enabled
        if (config.enable_file_logging) {
            if (config.file_path) |path| {
                const file_config = file.FileConfig{
                    .path = path,
                    .max_size = config.max_file_size,
                    .max_rotated_files = config.max_rotated_files,
                    .enable_rotation = config.enable_rotation,
                    .min_level = config.min_level,
                };
                var file_handler = try file.FileHandler.init(allocator, file_config);
                try logger.addHandler(file_handler.toLogHandler());
            }
        }

        return logger;
    }

    pub fn deinit(self: *Self) void {
        if (self.formatter) |fmt| {
            fmt.deinit();
        }
        // Deinit all handlers
        for (self.handlers.items) |handler| {
            handler.deinit();
        }
        self.handlers.deinit();
        self.allocator.destroy(self);
    }

    // In logger.zig - use null-safe access for formatter
    pub fn log(
        self: *Self,
        level: types.LogLevel,
        comptime fmt: []const u8,
        args: anytype,
        metadata: ?types.LogMetadata,
    ) !void {
        if (@intFromEnum(level) < @intFromEnum(self.config.min_level)) {
            return;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        // Format message
        var temp_buffer: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&temp_buffer);
        const message = try std.fmt.allocPrint(
            fba.allocator(),
            fmt,
            args,
        );

        // Use if statement to safely access formatter
        if (self.formatter) |formatter| {
            const formatted_message = try formatter.format(level, message, metadata);
            defer self.allocator.free(formatted_message);

            // Send to all handlers - pass the already formatted message
            for (self.handlers.items) |handler| {
                handler.writeFormattedLog(formatted_message) catch |log_error| {
                    std.debug.print("Handler error: {}\n", .{log_error});
                };
            }
        } else {
            // Fallback if formatter is null
            for (self.handlers.items) |handler| {
                handler.writeLog(level, message, metadata) catch |log_error| {
                    std.debug.print("Handler error: {}\n", .{log_error});
                };
            }
        }
    }

    // === Convenience (Infallible) Methods ===

    /// Logs an info-level message without the caller having to use `try` or `catch`.
    pub fn info(self: *Self, comptime fmt: []const u8, args: anytype, metadata: ?types.LogMetadata) void {
        _ = self.log(.info, fmt, args, metadata) catch |log_error| {
            std.debug.print("Logger.info error: {}\n", .{log_error});
        };

        try self.flush();
    }

    /// Logs a debug-level message.
    pub fn debug(self: *Self, comptime fmt: []const u8, args: anytype, metadata: ?types.LogMetadata) void {
        _ = self.log(.debug, fmt, args, metadata) catch |log_error| {
            std.debug.print("Logger.debug error: {}\n", .{log_error});
        };
        try self.flush();
    }

    /// Logs a warning-level message.
    pub fn warn(self: *Self, comptime fmt: []const u8, args: anytype, metadata: ?types.LogMetadata) void {
        _ = self.log(.warn, fmt, args, metadata) catch |log_error| {
            std.debug.print("Logger.warn error: {}\n", .{log_error});
        };
        try self.flush();
    }

    /// Logs an error-level message.
    pub fn err(self: *Self, comptime fmt: []const u8, args: anytype, metadata: ?types.LogMetadata) void {
        _ = self.log(.err, fmt, args, metadata) catch |log_error| {
            std.debug.print("Logger.error error: {}\n", .{log_error});
        };
        try self.flush();
    }

    // Add a new handler
    pub fn addHandler(self: *Self, handler: handlers.LogHandler) !void {
        try self.handlers.append(handler);
    }

    // Remove a handler
    pub fn removeHandler(self: *Self, handler: handlers.LogHandler) void {
        for (self.handlers.items, 0..) |h, i| {
            if (h.ctx == handler.ctx) {
                _ = self.handlers.orderedRemove(i);
                return;
            }
        }
    }

    // Convenience method for adding a network handler
    pub fn addNetworkHandler(self: *Self, network_config: network.NetworkConfig) !void {
        var net_handler = try network.NetworkHandler.init(self.allocator, network_config);
        try self.addHandler(net_handler.toLogHandler());
    }

    // Flush all handlers
    pub fn flush(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.handlers.items) |handler| {
            handler.flush() catch |flush_err| {
                std.debug.print("Flush error: {}\n", .{flush_err});
            };
        }
    }
};
