# API Reference

Complete API documentation for NexLog.

## Core Types

### Logger

Main logging interface.

```zig
pub const Logger = struct {
    pub fn init(allocator: Allocator, config: LogConfig) !Logger
    pub fn deinit(self: *Logger) void
    
    // Main logging methods
    pub fn log(self: *Logger, level: LogLevel, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) !void
    
    // Convenience methods (may return errors)
    pub fn trace(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) !void
    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) !void
    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) !void
    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) !void
    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) !void
    pub fn critical(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) !void
    
    // Non-failing convenience methods
    pub fn traceNoFail(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) void
    pub fn debugNoFail(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) void
    pub fn infoNoFail(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) void
    pub fn warnNoFail(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) void
    pub fn errNoFail(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) void
    pub fn criticalNoFail(self: *Logger, comptime fmt: []const u8, args: anytype, metadata: ?LogMetadata) void
    
    pub fn flush(self: *Logger) !void
};
```

### LogConfig

Configuration structure for logger initialization.

```zig
pub const LogConfig = struct {
    min_level: LogLevel = .info,
    enable_colors: bool = true,
    enable_file_logging: bool = false,
    file_path: []const u8 = "app.log",
    max_file_size: usize = 10 * 1024 * 1024,
    max_file_count: usize = 5,
    buffer_size: usize = 8 * 1024,
    flush_interval_ms: u64 = 5000,
    output_format: OutputFormat = .standard,
    custom_template: ?[]const u8 = null,
    timestamp_format: TimestampFormat = .unix,
    level_format: LevelFormat = .upper,
    include_metadata: bool = true,
};
```

### LogLevel

Available log levels.

```zig
pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err,
    critical,
    
    pub fn toString(self: LogLevel) []const u8
    pub fn toStringShort(self: LogLevel) []const u8
    pub fn fromString(str: []const u8) ?LogLevel
};
```

### LogMetadata

Metadata attached to log entries.

```zig
pub const LogMetadata = struct {
    timestamp: i64,
    thread_id: usize,
    file: []const u8,
    line: u32,
    function: []const u8,
    
    // Creation helpers
    pub fn create(src: std.builtin.SourceLocation) LogMetadata
    pub fn createWithTimestamp(timestamp: i64, src: std.builtin.SourceLocation) LogMetadata
    pub fn createWithThreadId(thread_id: usize, src: std.builtin.SourceLocation) LogMetadata
    pub fn minimal() LogMetadata
};
```

## Convenience Functions

### Metadata Helpers

```zig
// Create metadata from caller's source location
pub fn here(src: std.builtin.SourceLocation) LogMetadata

// Create metadata with custom timestamp
pub fn hereWithTimestamp(timestamp: i64, src: std.builtin.SourceLocation) LogMetadata

// Create metadata with custom thread ID
pub fn hereWithThreadId(thread_id: usize, src: std.builtin.SourceLocation) LogMetadata
```

Usage:
```zig
logger.info("Message", .{}, nexlog.here(@src()));
logger.warn("Custom time", .{}, nexlog.hereWithTimestamp(1640995200, @src()));
```

## Enums

### OutputFormat

```zig
pub const OutputFormat = enum {
    standard,  // Default format with placeholders
    json,      // JSON structured output
    compact,   // Minimal format
    custom,    // Use custom_template
};
```

### TimestampFormat

```zig
pub const TimestampFormat = enum {
    unix,      // Unix timestamp: 1640995200
    iso8601,   // ISO8601 format: 2022-01-01T00:00:00Z
};
```

### LevelFormat

```zig
pub const LevelFormat = enum {
    upper,       // INFO, WARN, ERROR
    lower,       // info, warn, error
    short_upper, // INF, WRN, ERR
    short_lower, // inf, wrn, err
};
```

## Structured Logging

### StructuredField

```zig
pub const StructuredField = struct {
    name: []const u8,
    value: FieldValue,
    attributes: ?std.StringHashMap([]const u8),
};
```

### FieldValue

```zig
pub const FieldValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: []const FieldValue,
    object: std.StringHashMap(FieldValue),
    null_value,
    
    pub fn toString(self: FieldValue, allocator: Allocator) ![]const u8
};
```

### Formatter

```zig
pub const Formatter = struct {
    pub fn init(allocator: Allocator, config: FormatConfig) !Formatter
    pub fn deinit(self: *Formatter) void
    
    pub fn format(
        self: *Formatter,
        level: LogLevel,
        message: []const u8,
        metadata: LogMetadata,
    ) ![]const u8
    
    pub fn formatStructured(
        self: *Formatter,
        level: LogLevel,
        message: []const u8,
        fields: []const StructuredField,
        metadata: LogMetadata,
    ) ![]const u8
};
```

## Initialization Functions

### Basic Initialization

```zig
// Initialize with default config
pub fn init(allocator: Allocator) !void

// Initialize with custom config  
pub fn initWithConfig(allocator: Allocator, config: LogConfig) !void

// Clean up resources
pub fn deinit() void

// Check if initialized
pub fn isInitialized() bool

// Get default logger instance
pub fn getDefaultLogger() *Logger
```

### Builder Pattern

```zig
pub const LogBuilder = struct {
    pub fn new(allocator: Allocator) LogBuilder
    pub fn withLevel(self: *LogBuilder, level: LogLevel) *LogBuilder
    pub fn withColors(self: *LogBuilder, enable: bool) *LogBuilder
    pub fn withFile(self: *LogBuilder, path: []const u8) *LogBuilder
    pub fn withBuffer(self: *LogBuilder, size: usize) *LogBuilder
    pub fn build(self: *LogBuilder) !Logger
};
```

Usage:
```zig
var logger = try LogBuilder.new(allocator)
    .withLevel(.debug)
    .withColors(true)
    .withFile("app.log")
    .build();
```

## Error Types

```zig
pub const LogError = error{
    OutOfMemory,
    FileNotFound,
    AccessDenied,
    InvalidConfig,
    InvalidTemplate,
    BufferFull,
    InitializationFailed,
};
```

## Utility Types

### CircularBuffer

```zig
pub const CircularBuffer = struct {
    pub fn init(allocator: Allocator, capacity: usize) !CircularBuffer
    pub fn deinit(self: *CircularBuffer) void
    pub fn write(self: *CircularBuffer, data: []const u8) !void
    pub fn read(self: *CircularBuffer, buffer: []u8) usize
    pub fn available(self: *CircularBuffer) usize
    pub fn capacity(self: *CircularBuffer) usize
};
```

### Pool

```zig
pub const Pool = struct {
    pub fn init(allocator: Allocator, capacity: usize) !Pool
    pub fn deinit(self: *Pool) void
    pub fn acquire(self: *Pool) ![]u8
    pub fn release(self: *Pool, buffer: []u8) void
};
```

## Thread Safety

All public API functions are thread-safe unless otherwise noted. Internal synchronization uses:

- Mutexes for logger state
- Atomic operations for counters
- Lock-free algorithms where possible

## Memory Management

- All allocations use the provided allocator
- Buffers are reused when possible to minimize allocations
- Call `deinit()` on all created objects to free resources
- Use `defer` statements to ensure cleanup

## Example Usage

```zig
const std = @import("std");
const nexlog = @import("nexlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger
    const config = nexlog.LogConfig{
        .min_level = .debug,
        .enable_colors = true,
    };
    const logger = try nexlog.Logger.init(allocator, config);
    defer logger.deinit();

    // Log messages
    try logger.info("Application started", .{}, nexlog.here(@src()));
    try logger.debug("Debug info: {}", .{42}, nexlog.here(@src()));
    
    // Non-failing convenience
    logger.warnNoFail("Warning message", .{}, nexlog.here(@src()));
    
    // Manual flush
    try logger.flush();
}
```
