const std = @import("std");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");
const buffer = @import("../utils/buffer.zig");
const handlers = @import("handlers.zig");

fn gzipAvailable() bool {
    // std gzip existed pre-0.15; gone in 0.15.1.
    const has_std_gzip = @hasDecl(std.compress, "gzip");
    return has_std_gzip;
}

var warned_no_gzip = std.atomic.Value(bool).init(false);
fn warnNoGzipOnce() void {
    if (!warned_no_gzip.swap(true, .acq_rel)) {
        std.log.warn("nexlog: gzip compression is deprecated/disabled in this build (Zig 0.15+). Rotated files will be uncompressed.", .{});
    }
}

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
    error_handler: ?*const errors.ErrorHandler = null,

    pub fn init(allocator: std.mem.Allocator, config: FileConfig, error_handler: ?*const errors.ErrorHandler) !*Self {
        // Validate config
        if (config.path.len == 0) return error.InvalidPath;
        if (config.buffer_size == 0) return error.InvalidBufferSize;
        if (config.max_size == 0) return error.InvalidMaxSize;

        var cfg = config;
        if (cfg.compression == .gzip and !comptime gzipAvailable()) {
            warnNoGzipOnce();
            cfg.compression = .none;
        }

        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        var circular_buf = try buffer.CircularBuffer.init(allocator, config.buffer_size);
        errdefer circular_buf.deinit();

        self.* = .{
            .allocator = allocator,
            .config = cfg,
            .file = null,
            .mutex = std.Thread.Mutex{},
            .circular_buffer = circular_buf,
            .last_flush = std.time.timestamp(),
            .current_size = std.atomic.Value(usize).init(0),
            .error_handler = error_handler,
        };

        // Safe file opening
        self.file = std.fs.cwd().createFile(config.path, .{
            .truncate = config.mode == .truncate,
        }) catch |err| {
            self.circular_buffer.deinit();
            self.handleError(err, "Failed to open log file");
            return err;
        };

        if (config.mode == .append) {
            self.current_size.store((try self.file.?.getEndPos()), .release);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        _ = self.flush() catch {};
        if (self.file) |file| file.close();
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
        const formatted = std.fmt.allocPrint(
            allocator,
            "[{d}] [{s}] {s}\n",
            .{ timestamp, level.toString(), message },
        ) catch |err| {
            self.handleError(err, "Failed to format log entry");
            return err;
        };

        // Write to buffer
        const bytes_written = self.circular_buffer.write(formatted) catch |err| {
            self.handleError(err, "Failed to write to circular buffer");
            return err;
        };
        const new_size = self.current_size.fetchAdd(bytes_written, .monotonic);

        // Check if file size exceeds max_size
        if (new_size + bytes_written >= self.config.max_size) {
            // Prioritize size-based rotation check
            try self.rotate();
        } else if (self.shouldRotate()) {
            self.rotate() catch |err| {
                self.handleError(err, "Failed to rotate log file");
                return err;
            };
        }

        // Check if we need to flush
        if (self.shouldFlush()) {
            self.flush() catch |err| {
                self.handleError(err, "Failed to flush log file");
                return err;
            };
        }
    }

    pub fn writeFormattedLog(self: *Self, formatted_message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Write to buffer directly
        const bytes_written = self.circular_buffer.write(formatted_message) catch |err| {
            self.handleError(err, "Failed to write formatted log to buffer");
            return err;
        };

        // Add newline if not present
        if (formatted_message.len > 0 and formatted_message[formatted_message.len - 1] != '\n') {
            _ = self.circular_buffer.write("\n") catch |err| {
                self.handleError(err, "Failed to write newline to buffer");
                return err;
            };
            _ = self.current_size.fetchAdd(bytes_written + 1, .monotonic);
        } else {
            _ = self.current_size.fetchAdd(bytes_written, .monotonic);
        }

        // Check rotation before writing
        if (self.config.enable_rotation and self.current_size.load(.monotonic) >= self.config.max_size) {
            self.rotate() catch |err| {
                self.handleError(err, "Failed to rotate log file");
                return err;
            };
        }

        // Check if we need to flush
        if (self.shouldFlush()) {
            self.flush() catch |err| {
                self.handleError(err, "Failed to flush log file");
                return err;
            };
        }
    }

    pub fn flush(self: *Self) !void {
        if (self.file) |file| {
            var temp_buffer: [4096]u8 = undefined;

            // Only try to read if there's data in the buffer
            if (self.circular_buffer.len() > 0) {
                while (true) {
                    const bytes_read = self.circular_buffer.read(&temp_buffer) catch |err| {
                        if (err == error.BufferUnderflow) {
                            break;
                        }
                        self.handleError(err, "Failed to read from circular buffer during flush");
                        return err;
                    };

                    if (bytes_read == 0) break;
                    file.writeAll(temp_buffer[0..bytes_read]) catch |err| {
                        self.handleError(err, "Failed to write to file during flush");
                        return err;
                    };
                }
                file.sync() catch |err| {
                    self.handleError(err, "Failed to sync file during flush");
                    return err;
                };
            }

            self.last_flush = std.time.timestamp();

            // Check rotation after flush
            if (self.config.enable_rotation and self.current_size.load(.monotonic) >= self.config.max_size) {
                self.rotate() catch |err| {
                    self.handleError(err, "Failed to rotate log file after flush");
                    return err;
                };
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

        if (!comptime gzipAvailable()) {
            return error.ZlibNotImplemented;
        }

        var source_file = try std.fs.cwd().openFile(source_path, .{});
        defer source_file.close();

        var dest_file = try std.fs.cwd().createFile(dest_path, .{});
        defer dest_file.close();

        if (comptime @hasDecl(std.compress, "gzip")) {
            try std.compress.gzip.compress(source_file.reader(), dest_file.writer(), .{});
        } else {
            return error.ZlibNotImplemented;
        }
    }

    fn rotate(self: *Self) !void {
        if (self.file) |file| {
            // Close before rename
            file.sync() catch {};
            file.close();
            self.file = null;

            // 1) Shift older files: path.(i-1) -> path.i
            var i: usize = self.config.max_rotated_files;
            while (i > 0) : (i -= 1) {
                const from = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ self.config.path, i - 1 });
                const to = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ self.config.path, i });
                defer {
                    self.allocator.free(from);
                    self.allocator.free(to);
                }

                if (i == self.config.max_rotated_files) {
                    // delete highest index if present
                    _ = std.fs.cwd().deleteFile(from) catch {};
                    continue;
                }

                _ = std.fs.cwd().rename(from, to) catch {};
            }

            // 2) Stage current as .0 (not .tmp)
            const zero_path = try std.fmt.allocPrint(self.allocator, "{s}.0", .{self.config.path});
            defer self.allocator.free(zero_path);

            // We had renamed path -> path.tmp earlier; move that into .0 now.
            const staged_tmp = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{self.config.path});
            defer self.allocator.free(staged_tmp);

            // If the tmp doesn't exist (edge cases), fall back to direct rename
            if (std.fs.cwd().rename(staged_tmp, zero_path)) |_| {
                // ok
            } else |_| {
                // if .tmp missing, try moving the live file (best effort)
                _ = std.fs.cwd().rename(self.config.path, zero_path) catch {};
            }

            // 3) Optionally compress .0 -> .0.gz atomically
            if (self.config.compression == .gzip) {
                const gz_tmp = try std.fmt.allocPrint(self.allocator, "{s}.gz.tmp", .{zero_path});
                const gz_final = try std.fmt.allocPrint(self.allocator, "{s}.gz", .{zero_path});
                defer {
                    self.allocator.free(gz_tmp);
                    self.allocator.free(gz_final);
                }

                // Try compression; on failure, keep uncompressed .0
                if (self.compressFile(zero_path, gz_tmp)) |_| {
                    // Publish compressed atomically and remove .0
                    _ = std.fs.cwd().rename(gz_tmp, gz_final) catch {};
                    _ = std.fs.cwd().deleteFile(zero_path) catch {};
                } else |e| {
                    // Compression unavailable/failed; keep .0
                    self.handleError(e, "Compression failed; kept uncompressed .0");
                    _ = std.fs.cwd().deleteFile(gz_tmp) catch {};
                }
            }

            // 4) Recreate the active log file

            self.file = try std.fs.cwd().createFile(self.config.path, .{});
            self.current_size.store(0, .release);
            self.config.last_rotation = std.time.timestamp();
        }
    }

    fn toErrorSet(err: anyerror) errors.Error {
        return switch (err) {
            error.BufferOverflow, error.BufferUnderflow, error.FlushFailed, error.CompactionFailed, error.BufferFull, error.InvalidAlignment => errors.Error.BufferError,
            error.InvalidConfiguration, error.InvalidLogLevel, error.InvalidBufferSize, error.InvalidRotationPolicy, error.InvalidFilterExpression, error.InvalidTimeFormat, error.InvalidPath, error.ConflictingOptions => errors.Error.ConfigError,
            error.FileNotFound, error.PermissionDenied, error.DirectoryNotFound, error.DiskFull, error.RotationLimitReached, error.InvalidFilePath, error.LockTimeout, error.NoSpaceLeft, error.InvalidUtf8, error.DiskQuota, error.FileTooBig, error.InputOutput, error.DeviceBusy, error.InvalidArgument, error.AccessDenied, error.BrokenPipe, error.SystemResources, error.OperationAborted, error.NotOpenForWriting, error.LockViolation, error.WouldBlock, error.ConnectionResetByPeer, error.ProcessNotFound, error.NoDevice, error.SharingViolation, error.PathAlreadyExists, error.PipeBusy, error.NameTooLong, error.InvalidWtf8, error.BadPathName, error.NetworkNotFound, error.AntivirusInterference, error.SymLinkLoop, error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.IsDir, error.NotDir, error.FileLocksNotSupported, error.FileBusy, error.FileSystem, error.ConnectionTimedOut, error.NotOpenForReading, error.SocketNotConnected, error.Canceled, error.OutOfMemory => errors.Error.IOError,
            else => errors.Error.Unexpected,
        };
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

    fn handleError(self: *Self, err: anyerror, msg: []const u8) void {
        const ctx = errors.makeError(
            Self.toErrorSet(err),
            msg,
            @src().file,
            @src().line,
        );
        if (self.error_handler) |handler| {
            handler.handle(ctx) catch {};
        } else {
            errors.defaultErrorHandler(ctx) catch {};
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
