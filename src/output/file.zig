const std = @import("std");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");
const buffer = @import("../utils/buffer.zig");
const handlers = @import("handlers.zig");

const FileRotationError = error{
    NoSpaceLeft,
    InvalidUtf8,
    DiskQuota,
    FileTooBig,
    InputOutput,
    DeviceBusy,
    InvalidArgument,
    AccessDenied,
    BrokenPipe,
    SystemResources,
    OperationAborted,
    NotOpenForWriting,
    LockViolation,
    WouldBlock,
    ConnectionResetByPeer,
    ProcessNotFound,
    NoDevice,
    Unexpected,
    OutOfMemory,
    PathAlreadyExists,
    FileNotFound,
    NameTooLong,
    SymLinkLoop,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    FileBusy,
    FileSystem,
    SharingViolation,
    PipeBusy,
    InvalidWtf8,
    BadPathName,
    NetworkNotFound,
    AntivirusInterference,
    IsDir,
    NotDir,
    FileLocksNotSupported,
    ConnectionTimedOut,
    NotOpenForReading,
    SocketNotConnected,
    Canceled,
    UnfinishedBits,
    ZlibNotImplemented,
    ZstdNotImplemented,
    ReadOnlyFileSystem,
    LinkQuotaExceeded,
    RenameAcrossMountPoints,
} || errors.BufferError || std.fs.File.WriteError;

pub const RotationMode = enum {
    size,
    time,
    both,
};

pub const CompressionType = enum {
    none,
    gzip,
};

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

    // New rotation options
    rotation_mode: RotationMode = .size,
    rotation_interval: u64 = 24 * 60 * 60, // Default: 24 hours in seconds
    compression: CompressionType = .none,
    last_rotation: i64 = 0, // Timestamp of last rotation
};

pub const FileHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: FileConfig,
    file: ?std.fs.File,
    mutex: std.Thread.Mutex,
    circular_buffer: *buffer.CircularBuffer,
    last_flush: i64,
    current_size: std.atomic.Value(usize),

    pub fn init(allocator: std.mem.Allocator, config: FileConfig) !*Self {
        // Validate config
        if (config.path.len == 0) return error.InvalidPath;
        if (config.buffer_size == 0) return error.InvalidBufferSize;
        if (config.max_size == 0) return error.InvalidMaxSize;

        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        var circular_buf = try buffer.CircularBuffer.init(allocator, config.buffer_size);
        errdefer circular_buf.deinit();

        self.* = .{
            .allocator = allocator,
            .config = config,
            .file = null,
            .mutex = std.Thread.Mutex{},
            .circular_buffer = circular_buf,
            .last_flush = std.time.timestamp(),
            .current_size = std.atomic.Value(usize).init(0),
        };

        // Safe file opening
        self.file = std.fs.cwd().createFile(config.path, .{
            .truncate = config.mode == .truncate,
        }) catch |err| {
            self.circular_buffer.deinit();
            return err;
        };

        if (config.mode == .append) {
            self.current_size.store((try self.file.?.getEndPos()), .release);
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
        const new_size = self.current_size.fetchAdd(bytes_written, .monotonic);

        // Check if file size exceeds max_size
        if (new_size + bytes_written >= self.config.max_size) {
            // Prioritize size-based rotation check
            try self.rotate();
        } else if (self.shouldRotate()) {
            try self.rotate();
        }

        // Check if we need to flush
        if (self.shouldFlush()) {
            try self.flush();
        }
    }

    pub fn writeFormattedLog(self: *Self, formatted_message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Write to buffer directly
        const bytes_written = try self.circular_buffer.write(formatted_message);

        // Add newline if not present
        if (formatted_message.len > 0 and formatted_message[formatted_message.len - 1] != '\n') {
            _ = try self.circular_buffer.write("\n");
            _ = self.current_size.fetchAdd(bytes_written + 1, .monotonic);
        } else {
            _ = self.current_size.fetchAdd(bytes_written, .monotonic);
        }

        // Check rotation
        if (self.shouldRotate()) {
            try self.rotate();
        }

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
            if (self.config.enable_rotation and self.current_size.load(.monotonic) >= self.config.max_size) {
                try self.rotate();
            }
        }
    }

    fn shouldFlush(self: *Self) bool {
        const now = std.time.timestamp();
        return self.circular_buffer.len() > self.config.buffer_size / 2 or
            now - self.last_flush >= self.config.flush_interval_ms / 1000;
    }

    fn compressFile(self: *Self, source_path: []const u8, dest_path: []const u8) !void {
        if (self.config.compression == .none) return;

        var source_file = try std.fs.cwd().openFile(source_path, .{});
        defer source_file.close();

        var dest_file = try std.fs.cwd().createFile(dest_path, .{});
        defer dest_file.close();

        try std.compress.gzip.compress(source_file.reader(), dest_file.writer(), .{});
    }

    fn shouldRotate(self: *Self) bool {
        if (!self.config.enable_rotation) return false;

        const current_size = self.current_size.load(.monotonic);
        const now = std.time.timestamp();

        return switch (self.config.rotation_mode) {
            .size => current_size >= self.config.max_size,
            .time => (now - self.config.last_rotation) >= self.config.rotation_interval,
            .both => current_size >= self.config.max_size or
                (now - self.config.last_rotation) >= self.config.rotation_interval,
        };
    }

    fn formatRotatedFileName(self: *Self, index: usize) ![]const u8 {
        const timestamp = std.time.timestamp();

        // Start with a copy of the pattern
        var result = try self.allocator.dupe(u8, self.config.rotation_pattern);
        errdefer self.allocator.free(result);

        // Replace {path}
        if (std.mem.indexOf(u8, result, "{path}")) |_| {
            const new_result = try std.mem.replaceOwned(u8, self.allocator, result, "{path}", self.config.path);
            self.allocator.free(result);
            result = new_result;
        }

        // Replace {timestamp}
        if (std.mem.indexOf(u8, result, "{timestamp}")) |_| {
            const timestamp_str = try std.fmt.allocPrint(self.allocator, "{d}", .{timestamp});
            defer self.allocator.free(timestamp_str);
            const new_result = try std.mem.replaceOwned(u8, self.allocator, result, "{timestamp}", timestamp_str);
            self.allocator.free(result);
            result = new_result;
        }

        // Replace {index}
        if (std.mem.indexOf(u8, result, "{index}")) |_| {
            const index_str = try std.fmt.allocPrint(self.allocator, "{d}", .{index});
            defer self.allocator.free(index_str);
            const new_result = try std.mem.replaceOwned(u8, self.allocator, result, "{index}", index_str);
            self.allocator.free(result);
            result = new_result;
        }

        return result;
    }

    fn rotate(self: *Self) FileRotationError!void {
        if (self.file) |file| {
            const timestamp = std.time.timestamp();

            // Flush and close current file
            try self.flush();
            file.close();
            self.file = null;

            // Shift existing rotated files
            var i: usize = self.config.max_rotated_files;
            while (i > 0) : (i -= 1) {
                const old_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.{d}",
                    .{ self.config.path, i - 1 },
                );
                defer self.allocator.free(old_path);

                // Skip if this is the highest index
                if (i == self.config.max_rotated_files) {
                    // Delete the highest index file if it exists
                    std.fs.cwd().deleteFile(old_path) catch |err| switch (err) {
                        error.FileNotFound => {}, // Ignore if file doesn't exist
                        else => {}, // Ignore other errors and continue
                    };
                    continue;
                }

                const new_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.{d}",
                    .{ self.config.path, i },
                );
                defer self.allocator.free(new_path);

                // Try to rename, ignore errors if file doesn't exist
                std.fs.cwd().rename(old_path, new_path) catch |err| switch (err) {
                    error.FileNotFound => {}, // Skip if the source doesn't exist
                    else => {}, // Ignore other errors and continue
                };
            }

            // Move current file to .1
            const backup_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}.1",
                .{self.config.path},
            );
            defer self.allocator.free(backup_path);

            std.fs.cwd().rename(self.config.path, backup_path) catch |err| switch (err) {
                error.FileNotFound => {}, // Might happen if log file was deleted
                else => {}, // Ignore other errors and continue
            };

            // Compress the rotated file if needed
            if (self.config.compression == .gzip) {
                const compressed_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.gz",
                    .{backup_path},
                );
                defer self.allocator.free(compressed_path);

                self.compressFile(backup_path, compressed_path) catch {};
                std.fs.cwd().deleteFile(backup_path) catch {};
            }

            // Create new file
            self.file = try std.fs.cwd().createFile(self.config.path, .{});
            self.current_size.store(0, .release);
            self.config.last_rotation = timestamp;
        }
    }
    // Interface conversion method - fixed to use the new handler interface
    pub fn toLogHandler(self: *Self) handlers.LogHandler {
        return handlers.LogHandler.init(
            self,
            .file,
            FileHandler.writeLog,
            FileHandler.writeFormattedLog,
            FileHandler.flush,
            FileHandler.deinit,
        );
    }
};
