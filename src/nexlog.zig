// src/nexlog.zig
const std = @import("std");

pub const core = struct {
    pub const logger = @import("core/logger.zig");
    pub const config = @import("core/config.zig");
    pub const init = @import("core/init.zig");
    pub const errors = @import("core/errors.zig");
    pub const types = @import("core/types.zig");
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

// Re-export main types and functions
pub const Logger = core.logger.Logger;
pub const LogLevel = core.types.LogLevel;
pub const LogConfig = core.config.LogConfig;
pub const LogMetadata = core.types.LogMetadata;

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

// Metadata creation helpers
/// Create metadata automatically capturing source location
pub fn here() LogMetadata {
    return LogMetadata.create(@src());
}

/// Create metadata with custom timestamp
pub fn hereWithTimestamp(timestamp: i64) LogMetadata {
    return LogMetadata.createWithTimestamp(timestamp, @src());
}

/// Create metadata with custom thread ID
pub fn hereWithThreadId(thread_id: usize) LogMetadata {
    return LogMetadata.createWithThreadId(thread_id, @src());
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
