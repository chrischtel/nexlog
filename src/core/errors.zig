// errors.zig
const std = @import("std");

pub const LogError = error{
    BufferFull,
    InvalidLogLevel,
    MessageTooLarge,
    FileLockFailed,
    FileRotationFailed,
    InvalidConfiguration,
    ThreadInitFailed,
    MetadataError,
    FormattingError,
    FilterError,
    AlreadyInitialized,
};

pub const FileError = error{
    FileNotFound,
    PermissionDenied,
    DirectoryNotFound,
    DiskFull,
    RotationLimitReached,
    InvalidFilePath,
    LockTimeout,
};

pub const BufferError = error{
    BufferOverflow,
    BufferUnderflow,
    InvalidAlignment,
    FlushFailed,
    CompactionFailed,
    BufferFull,
};

pub const ConfigError = error{
    InvalidLogLevel,
    InvalidBufferSize,
    InvalidRotationPolicy,
    InvalidFilterExpression,
    InvalidTimeFormat,
    InvalidPath,
    ConflictingOptions,
};

pub const MemoryError = error{
    OutOfMemory,
};

/// Comprehensive error set combining all logging-related and memory errors
pub const Error = LogError || FileError || BufferError || ConfigError || std.fs.File.OpenError || std.fs.File.WriteError || MemoryError;

pub const ErrorContext = struct {
    file: []const u8,
    line: u32,
    error_type: Error,
    message: []const u8,
    timestamp: i64,

    pub fn init(
        error_type: Error,
        message: []const u8,
        file: []const u8,
        line: u32,
    ) ErrorContext {
        return .{
            .error_type = error_type,
            .message = message,
            .file = file,
            .line = line,
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn format(self: ErrorContext, writer: anytype) !void {
        try writer.print(
            "Error[{d}] {s}:{d}: {s} - {s}\n",
            .{
                self.timestamp,
                self.file,
                self.line,
                @errorName(self.error_type),
                self.message,
            },
        );
    }
};

pub const ErrorHandler = struct {
    pub const ErrorFn = *const fn (context: ErrorContext) Error!void;

    handler_fn: ErrorFn,
    max_retries: u32,
    retry_delay_ms: u32,

    pub fn init(handler_fn: ErrorFn, max_retries: u32, retry_delay_ms: u32) ErrorHandler {
        return .{
            .handler_fn = handler_fn,
            .max_retries = max_retries,
            .retry_delay_ms = retry_delay_ms,
        };
    }

    pub fn handle(self: *const ErrorHandler, context: ErrorContext) Error!void {
        var retries: u32 = 0;
        while (retries < self.max_retries) : (retries += 1) {
            self.handler_fn(context) catch |err| {
                if (retries == self.max_retries - 1) return err;
                std.time.sleep(self.retry_delay_ms * std.time.ns_per_ms);
                continue;
            };
            break;
        }
    }
};

pub fn makeError(
    error_type: Error,
    message: []const u8,
    file: []const u8,
    line: u32,
) ErrorContext {
    return ErrorContext.init(error_type, message, file, line);
}

pub fn defaultErrorHandler(context: ErrorContext) Error!void {
    const stderr = std.io.getStdErr().writer();
    try context.format(stderr);
}
