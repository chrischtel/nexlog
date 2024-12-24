const std = @import("std");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");
const buffer = @import("../utils/buffer.zig");
const handlers = @import("handlers.zig");

pub const FileConfig = struct {
    path: []const u8,
    mode: enum {
        append,
        truncate,
    } = .append,
    max_size: usize = 10 * 1024 * 1024, // 10MB default
    enable_rotation: bool = true,
    max_rotated_files: usize = 5,
    buffer_size: usize = 4096,
    flush_interval_ms: u32 = 1000,
    min_level: types.LogLevel = .debug,
};

pub const FileHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: FileConfig,
    file: ?std.fs.File,
    mutex: std.Thread.Mutex,
    circular_buffer: *buffer.CircularBuffer,
    last_flush: i64,
    current_size: usize,

    pub fn init(allocator: std.mem.Allocator, config: FileConfig) !*Self {
        var self = try allocator.create(Self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .file = null,
            .mutex = std.Thread.Mutex{},
            .circular_buffer = try buffer.CircularBuffer.init(allocator, config.buffer_size),
            .last_flush = std.time.timestamp(),
            .current_size = 0,
        };

        // Open or create the file
        self.file = try std.fs.cwd().createFile(config.path, .{
            .truncate = config.mode == .truncate,
        });

        // Get initial file size if appending
        if (config.mode == .append) {
            self.current_size = try self.file.?.getEndPos();
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.file) |file| {
            file.close();
        }
        self.circular_buffer.deinit();
        self.allocator.destroy(self);
    }

    pub fn writeLog(self: *Self, level: types.LogLevel, message: []const u8, metadata: ?types.LogMetadata) !void {
        // Skip if below minimum level
        if (@intFromEnum(level) < @intFromEnum(self.config.min_level)) {
            return;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        var fba = std.heap.FixedBufferAllocator.init(self.circular_buffer.buffer);
        const allocator = fba.allocator();

        // Format log entry
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();
        const formatted = try std.fmt.allocPrint(
            allocator,
            "[{d}] [{s}] {s}\n",
            .{ timestamp, level.toString(), message },
        );

        // Write to buffer
        const bytes_written = try self.circular_buffer.write(formatted);
        self.current_size += bytes_written;

        // Check if we need to flush
        if (self.shouldFlush()) {
            try self.flush();
        }
    }

    pub fn flush(self: *Self) !void {
        if (self.file) |file| {
            var temp_buffer: [4096]u8 = undefined;

            // Only try to read if there's data in the buffer
            if (self.circular_buffer.len() > 0) {
                while (true) {
                    const bytes_read = self.circular_buffer.read(&temp_buffer) catch |err| {
                        if (err == errors.BufferError.BufferUnderflow) {
                            break;
                        }
                        return err;
                    };

                    if (bytes_read == 0) break;
                    try file.writeAll(temp_buffer[0..bytes_read]);
                }
                try file.sync();
            }

            self.last_flush = std.time.timestamp();

            // Check rotation after flush
            if (self.config.enable_rotation and self.current_size >= self.config.max_size) {
                try self.rotate();
            }
        }
    }

    fn shouldFlush(self: *Self) bool {
        const now = std.time.timestamp();
        return self.circular_buffer.len() > self.config.buffer_size / 2 or
            now - self.last_flush >= self.config.flush_interval_ms / 1000;
    }

    fn rotate(self: *Self) !void {
        if (self.file) |file| {
            file.close();
            self.file = null;

            // Rotate existing files
            var i: usize = self.config.max_rotated_files;
            while (i > 0) : (i -= 1) {
                const old_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.{d}",
                    .{ self.config.path, i - 1 },
                );
                defer self.allocator.free(old_path);

                const new_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.{d}",
                    .{ self.config.path, i },
                );
                defer self.allocator.free(new_path);

                std.fs.cwd().rename(old_path, new_path) catch |err| switch (err) {
                    error.FileNotFound => continue,
                    else => return err,
                };
            }

            // Rename current log file
            const backup_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}.1",
                .{self.config.path},
            );
            defer self.allocator.free(backup_path);

            try std.fs.cwd().rename(self.config.path, backup_path);

            // Create new file
            self.file = try std.fs.cwd().createFile(self.config.path, .{});
            self.current_size = 0;
        }
    }

    // Interface conversion method
    pub fn toLogHandler(self: *Self) handlers.LogHandler {
        return handlers.LogHandler.init(
            self,
            writeLog,
            flush,
            deinit,
        );
    }
};
