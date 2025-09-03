const std = @import("std");
const types = @import("../core/types.zig");
const async_core = @import("core.zig");
const format = @import("../utils/format.zig");

pub const AsyncConsoleConfig = struct {
    use_stderr: bool = false,
    min_level: types.LogLevel = .debug,
    enable_colors: bool = true,
    fast_mode: bool = false,
    buffer_size: usize = 4096,
    show_source_location: bool = true,
    show_function: bool = false,
    show_thread_id: bool = false,
};

pub const AsyncConsoleHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: AsyncConsoleConfig,
    formatter: ?*format.Formatter,
    buffer: std.ArrayList(u8),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, config: AsyncConsoleConfig) !*Self {
        const handler = try allocator.create(Self);

        // Create formatter for non-fast mode
        var formatter: ?*format.Formatter = null;
        if (!config.fast_mode) {
            const fmt_config = format.FormatConfig{
                .template = if (config.enable_colors)
                    "{color}[{timestamp}] [{level}]{reset} {message}"
                else
                    "[{timestamp}] [{level}] {message}",
                .timestamp_format = .unix,
                .use_color = config.enable_colors,
            };
            formatter = try format.Formatter.init(allocator, fmt_config);
        }

        handler.* = .{
            .allocator = allocator,
            .config = config,
            .formatter = formatter,
            .buffer = .empty,
            .mutex = std.Thread.Mutex{},
        };

        return handler;
    }

    pub fn deinit(self: *Self) void {
        if (self.formatter) |formatter| {
            formatter.deinit();
        }
        self.buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn logAsync(self: *Self, entry: async_core.LogEntry) !void {
        if (@intFromEnum(entry.level) < @intFromEnum(self.config.min_level)) {
            return;
        }

        // Handle special flush command
        if (std.mem.eql(u8, entry.message, "__FLUSH__")) {
            return self.flushAsync();
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        self.buffer.clearRetainingCapacity();

        if (self.config.fast_mode) {
            // Ultra-fast mode: minimal formatting
            try self.buffer.writer(self.allocator).print("[{d}] {s}\n", .{ entry.timestamp, entry.message });
        } else {
            // Use stack buffer for formatting to avoid additional allocations
            var format_buffer: [2048]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&format_buffer);
            const writer = fbs.writer();

            // Fast path: Simple format without metadata
            if (entry.metadata == null or (!self.config.show_source_location and !self.config.show_function and !self.config.show_thread_id)) {
                if (self.config.enable_colors) {
                    try writer.print("{s}[{d}] [{s}]\x1b[0m {s}\n", .{
                        entry.level.toColor(),
                        entry.timestamp,
                        entry.level.toString(),
                        entry.message,
                    });
                } else {
                    try writer.print("[{d}] [{s}] {s}\n", .{
                        entry.timestamp,
                        entry.level.toString(),
                        entry.message,
                    });
                }
            } else {
                // Full format with metadata
                if (self.config.enable_colors) {
                    try writer.print("{s}[{d}] [{s}]\x1b[0m", .{
                        entry.level.toColor(),
                        entry.timestamp,
                        entry.level.toString(),
                    });
                } else {
                    try writer.print("[{d}] [{s}]", .{
                        entry.timestamp,
                        entry.level.toString(),
                    });
                }

                // Add optional metadata components
                if (entry.metadata) |m| {
                    if (self.config.show_source_location) {
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

                try writer.print(" {s}\n", .{entry.message});
            }

            try self.buffer.appendSlice(self.allocator, fbs.getWritten());
        }

        // Write to output in single operation (non-blocking for console)
        var output_buffer: [1024]u8 = undefined;
        if (self.config.use_stderr) {
            var stderr_writer = std.fs.File.stderr().writer(&output_buffer);
            const stderr = &stderr_writer.interface;
            _ = stderr.writeAll(self.buffer.items) catch |err| {
                std.debug.print("Console write error: {}\n", .{err});
            };
            stderr.flush() catch |err| {
                std.debug.print("Console flush error: {}\n", .{err});
            };
        } else {
            var stdout_writer = std.fs.File.stdout().writer(&output_buffer);
            const stdout = &stdout_writer.interface;
            _ = stdout.writeAll(self.buffer.items) catch |err| {
                std.debug.print("Console write error: {}\n", .{err});
            };
            stdout.flush() catch |err| {
                std.debug.print("Console flush error: {}\n", .{err});
            };
        }
    }

    pub fn flushAsync(self: *Self) !void {
        // Console output is typically immediately flushed by the OS
        // But we can force a sync for safety
        const out = if (self.config.use_stderr)
            std.fs.File.stderr()
        else
            std.fs.File.stdout();

        try out.sync();
    }

    /// Convert to generic AsyncLogHandler interface
    pub fn toAsyncLogHandler(self: *Self) async_core.AsyncLogHandler {
        return async_core.AsyncLogHandler.init(
            self,
            AsyncConsoleHandler.logAsync,
            AsyncConsoleHandler.flushAsync,
            AsyncConsoleHandler.deinit,
        );
    }
};
