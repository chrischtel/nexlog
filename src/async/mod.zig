// Async logging module - provides non-blocking logging for high-performance applications
const std = @import("std");

pub const core = @import("core.zig");
pub const logger = @import("logger.zig");
pub const console = @import("console.zig");
pub const file = @import("file.zig");

// Re-export main types
pub const AsyncLogger = logger.AsyncLogger;
pub const AsyncLogConfig = logger.AsyncLogConfig;
pub const AsyncLoggerStats = logger.AsyncLoggerStats;

pub const AsyncLogEntry = core.LogEntry;
pub const AsyncLogQueue = core.AsyncLogQueue;
pub const AsyncLogProcessor = core.AsyncLogProcessor;
pub const AsyncLogHandler = core.AsyncLogHandler;

pub const AsyncConsoleHandler = console.AsyncConsoleHandler;
pub const AsyncConsoleConfig = console.AsyncConsoleConfig;

pub const AsyncFileHandler = file.AsyncFileHandler;
pub const AsyncFileConfig = file.AsyncFileConfig;
pub const AsyncFileStats = file.AsyncFileStats;
