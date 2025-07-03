// src/nexlog.zig
const std = @import("std");

pub const core = struct {
    pub const logger = @import("core/logger.zig");
    pub const config = @import("core/config.zig");
    pub const init = @import("core/init.zig");
    pub const errors = @import("core/errors.zig");
    pub const types = @import("core/types.zig");
    pub const context = @import("core/context.zig");
};

pub const utils = struct {
    pub const buffer = @import("utils/buffer.zig");
    pub const pool = @import("utils/pool.zig");
    pub const json = @import("utils/json.zig");
    pub const format = @import("utils/format.zig");
};

pub const output = struct {
    pub const console = @import("output/console.zig");
    pub const file = @import("output/file.zig");
    pub const handler = @import("output/handlers.zig");
    pub const network = @import("output/network.zig");
    pub const json_handler = @import("output/json.zig");
};

pub const async_logging = @import("async/mod.zig");

// Re-export main types and functions
pub const Logger = core.logger.Logger;
pub const LogLevel = core.types.LogLevel;
pub const LogConfig = core.config.LogConfig;
pub const LogMetadata = core.types.LogMetadata;
pub const LogContext = core.types.LogContext;
pub const ContextManager = core.context.ContextManager;

// Re-export initialization functions
pub const init = core.init.init;
pub const initWithConfig = core.init.initWithConfig;
pub const deinit = core.init.deinit;
pub const isInitialized = core.init.isInitialized;
pub const getDefaultLogger = core.init.getDefaultLogger;
pub const LogBuilder = core.init.LogBuilder;

// Re-export utility functionality
pub const CircularBuffer = utils.buffer.CircularBuffer;
pub const Pool = utils.pool.Pool;
pub const JsonValue = utils.json.JsonValue;
pub const JsonError = utils.json.JsonError;

pub const BufferHealth = utils.buffer.BufferHealth;
pub const BufferStats = utils.buffer.BufferStats;

// Re-export async logging
pub const AsyncLogger = async_logging.AsyncLogger;
pub const AsyncLogConfig = async_logging.AsyncLogConfig;
pub const AsyncConsoleHandler = async_logging.AsyncConsoleHandler;
pub const AsyncFileHandler = async_logging.AsyncFileHandler;
pub const AsyncLogHandler = async_logging.AsyncLogHandler;

// Metadata creation helpers
// The proper Zig way: users pass @src() explicitly to capture correct location

/// Create metadata from caller's source location
/// Usage: nexlog.here(@src())
pub inline fn here(src: std.builtin.SourceLocation) LogMetadata {
    return LogMetadata.create(src);
}

/// Create metadata with custom timestamp from caller's source location
/// Usage: nexlog.hereWithTimestamp(timestamp, @src())
pub inline fn hereWithTimestamp(timestamp: i64, src: std.builtin.SourceLocation) LogMetadata {
    return LogMetadata.createWithTimestamp(timestamp, src);
}

/// Create metadata with custom thread ID from caller's source location
/// Usage: nexlog.hereWithThreadId(thread_id, @src())
pub inline fn hereWithThreadId(thread_id: usize, src: std.builtin.SourceLocation) LogMetadata {
    return LogMetadata.createWithThreadId(thread_id, src);
}

// Context tracking helpers
/// Create metadata with automatic context from ContextManager
/// Usage: nexlog.hereWithContext(@src())
pub inline fn hereWithContext(src: std.builtin.SourceLocation) LogMetadata {
    const context = ContextManager.getContext();
    return LogMetadata.createWithContext(src, context);
}

/// Set request context for current thread
/// Usage: nexlog.setRequestContext("req-12345", "user_login")
pub fn setRequestContext(request_id: []const u8, operation: ?[]const u8) void {
    ContextManager.setRequestContext(request_id, operation);
}

/// Add correlation ID to existing context
/// Usage: nexlog.correlate("corr-67890")
pub fn correlate(correlation_id: []const u8) void {
    ContextManager.addCorrelation(correlation_id);
}

/// Clear context for current thread
/// Usage: nexlog.clearContext()
pub fn clearContext() void {
    ContextManager.clearContext();
}

// Example test
test "basic log test" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cfg = LogConfig{
        .min_level = .debug,
        .enable_colors = false,
        .enable_file_logging = false,
    };

    var log = try Logger.init(allocator, cfg);
    defer log.deinit();

    try log.log(.err, "Test message", .{}, null);
}
