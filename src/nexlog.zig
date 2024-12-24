// src/nexlog.zig
const std = @import("std");

pub const core = struct {
    pub const logger = @import("core/logger.zig");
    pub const config = @import("core/config.zig");
    pub const init = @import("core/init.zig");
    pub const errors = @import("core/errors.zig");
    pub const types = @import("core/types.zig");
};

pub const analysis = struct {
    pub const patterns = @import("analysis/patterns.zig");
    // pub const predictor = @import("analysis/predictor.zig");
    // pub const correlator = @import("analysis/correlator.zig");
};

pub const utils = struct {
    pub const buffer = @import("utils/buffer.zig");
    pub const pool = @import("utils/pool.zig");
};

pub const output = struct {
    pub const console = @import("output/console.zig");
    pub const file = @import("output/file.zig");
    pub const handler = @import("output/handlers.zig");
};

// Re-export main types and functions
pub const Logger = core.logger.Logger;
pub const LogLevel = core.types.LogLevel;
pub const LogConfig = core.config.LogConfig;
pub const LogMetadata = core.types.LogMetadata;
pub const LogError = core.errors.LogError;

// Re-export initialization functions
pub const init = core.init.init;
pub const initWithConfig = core.init.initWithConfig;
pub const deinit = core.init.deinit;
pub const isInitialized = core.init.isInitialized;
pub const getDefaultLogger = core.init.getDefaultLogger;
pub const LogBuilder = core.init.LogBuilder;

// Re-export pattern analysis types and functions
pub const PatternType = core.types.PatternType;
pub const PatternVariable = core.types.PatternVariable;
pub const VarType = core.types.VarType;
pub const PatternMetadata = core.types.PatternMetadata;
pub const PatternMatch = core.types.PatternMatch;
pub const PatternConfig = core.types.PatternConfig;

// Re-export analysis functionality
pub const PatternAnalyzer = analysis.patterns.PatternAnalyzer;
pub const Pattern = analysis.patterns.Pattern;
// pub const PatternPredictor = analysis.predictor.PatternPredictor;
// pub const PatternCorrelator = analysis.correlator.PatternCorrelator;
pub const CategoryRule = analysis.patterns.CategoryRule;
pub const VariableRule = analysis.patterns.VariableRule;

// Re-export utility functionality
pub const CircularBuffer = utils.buffer.CircularBuffer;
pub const Pool = utils.pool.Pool;

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
