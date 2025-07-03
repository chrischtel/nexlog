# Nexlog Async Quick Start Guide

## Overview
Nexlog now supports high-performance asynchronous logging designed for async runtimes like Zuki. The async system provides non-blocking operations, backpressure handling, and multi-threaded safety.

## Basic Setup

### 1. Import Async Module
```zig
const std = @import("std");
const nexlog = @import("nexlog");
const async_logging = nexlog.async_logging;
```

### 2. Initialize Async Logger
```zig
// Create allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

// Create async logger with queue size
var logger = try async_logging.AsyncLogger.init(allocator, 10000); // 10k queue size
defer logger.deinit();
```

### 3. Add Handlers

#### Console Handler (Fast Mode)
```zig
// Fast console output (no colors, minimal formatting)
var console_handler = async_logging.AsyncConsoleHandler.init(allocator, .{
    .fast_mode = true,
    .use_colors = false,
});
defer console_handler.deinit();

try logger.addHandler(&console_handler.handler);
```

#### File Handler with Rotation
```zig
// File handler with automatic rotation
var file_handler = try async_logging.AsyncFileHandler.init(allocator, .{
    .file_path = "logs/app.log",
    .max_file_size = 10 * 1024 * 1024, // 10MB
    .max_files = 5,
    .buffer_size = 8192,
    .flush_interval_ms = 1000, // Flush every second
});
defer file_handler.deinit();

try logger.addHandler(&file_handler.handler);
```

### 4. Start Processing
```zig
// Start background processing thread
try logger.start();
defer logger.stop(); // Always stop before deinit
```

## Configuration Options

### AsyncLogger Configuration
```zig
// Queue size affects memory usage and backpressure behavior
var logger = try AsyncLogger.init(allocator, queue_size);

// Default: 10,000 entries
// High-load: 50,000+ entries
// Low-memory: 1,000-5,000 entries
```

### Console Handler Options
```zig
const console_config = AsyncConsoleHandler.Config{
    .fast_mode = true,        // Skip formatting for performance
    .use_colors = false,      // Disable ANSI colors
    .include_metadata = true, // Show file:line info
    .timestamp_format = .iso, // .iso, .unix, .none
};

var console_handler = AsyncConsoleHandler.init(allocator, console_config);
```

### File Handler Options
```zig
const file_config = AsyncFileHandler.Config{
    .file_path = "logs/app.log",
    .max_file_size = 10 * 1024 * 1024,  // 10MB rotation
    .max_files = 5,                      // Keep 5 rotated files
    .buffer_size = 8192,                 // 8KB write buffer
    .flush_interval_ms = 1000,           // Auto-flush every 1s
    .compression = .none,                // .none, .gzip (future)
    .create_dirs = true,                 // Auto-create log directories
};

var file_handler = try AsyncFileHandler.init(allocator, file_config);
```

## Logging Usage

### Basic Async Logging
```zig
// Non-blocking async log calls
try logger.logAsync(.info, "Application started", null);
try logger.logAsync(.error, "Database connection failed", null);
try logger.logAsync(.debug, "Processing user request", null);

// With metadata (file/line info)
const metadata = nexlog.types.LogMetadata{
    .file = @src().file,
    .line = @src().line,
    .function = @src().fn_name,
};
try logger.logAsync(.warn, "Low memory warning", metadata);
```

### Convenience Methods
```zig
// Level-specific methods (automatically include metadata)
try logger.infoAsync("User login successful");
try logger.errorAsync("Failed to save file");
try logger.debugAsync("Cache hit for key: {s}", .{key});
try logger.warnAsync("High CPU usage: {d}%", .{cpu_percent});
```

### Formatted Logging
```zig
// String formatting support
try logger.infoAsync("User {s} logged in from {s}", .{username, ip_address});
try logger.errorAsync("Error code: {d}, message: {s}", .{error_code, error_msg});

// Complex formatting
try logger.debugAsync("Request processed in {d}ms, status: {d}", .{duration_ms, status_code});
```

## Performance Patterns

### High-Throughput Logging
```zig
// For high-frequency logging, use larger queue
var logger = try AsyncLogger.init(allocator, 50000);

// Use fast mode for console
var console_handler = AsyncConsoleHandler.init(allocator, .{
    .fast_mode = true,
    .use_colors = false,
});

// Larger file buffer for better I/O performance
var file_handler = try AsyncFileHandler.init(allocator, .{
    .file_path = "logs/high_throughput.log",
    .buffer_size = 32768, // 32KB buffer
    .flush_interval_ms = 5000, // Less frequent flushing
});
```

### Low-Latency Applications
```zig
// Smaller queue for predictable memory usage
var logger = try AsyncLogger.init(allocator, 1000);

// Fast console with minimal formatting
var console_handler = AsyncConsoleHandler.init(allocator, .{
    .fast_mode = true,
    .include_metadata = false, // Skip file:line for speed
});

// Smaller buffer, more frequent flushing
var file_handler = try AsyncFileHandler.init(allocator, .{
    .buffer_size = 4096,
    .flush_interval_ms = 100, // Flush every 100ms
});
```

## Error Handling

### Backpressure Management
```zig
// Check queue status
const stats = logger.getStats();
if (stats.queue_size > stats.max_size * 0.8) {
    // Queue getting full - consider reducing log volume
    std.log.warn("Log queue at {d}% capacity", .{stats.queue_size * 100 / stats.max_size});
}

// Monitor dropped messages
if (stats.dropped_count > 0) {
    std.log.err("Dropped {d} log messages due to backpressure", .{stats.dropped_count});
}
```

### Graceful Shutdown
```zig
// Always stop logger before deinit
logger.stop(); // Processes remaining queue entries
logger.deinit(); // Cleanup resources

// Or use defer for automatic cleanup
defer {
    logger.stop();
    logger.deinit();
}
```

## Integration with Zuki

### Async Runtime Compatible
```zig
// Nexlog async operations don't block the event loop
pub fn handleRequest(zuki_context: *ZukiContext) !void {
    // This won't block Zuki's async execution
    try logger.infoAsync("Handling request: {s}", .{zuki_context.request_id});
    
    // Your async business logic here
    const result = try processRequestAsync(zuki_context);
    
    // Non-blocking success log
    try logger.infoAsync("Request completed: {s}", .{result});
}
```

### Thread Safety
```zig
// Safe to call from multiple Zuki tasks/threads
const handles = try std.Thread.spawn(.{}, workerTask, .{logger});
// Multiple tasks can log concurrently without coordination
```

## Quick Examples

### Minimal Setup
```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var logger = try async_logging.AsyncLogger.init(allocator, 10000);
defer { logger.stop(); logger.deinit(); }

var console = async_logging.AsyncConsoleHandler.init(allocator, .{});
defer console.deinit();

try logger.addHandler(&console.handler);
try logger.start();

try logger.infoAsync("Hello, async world!");
```

### Production Setup
```zig
// Production configuration with file rotation
var logger = try async_logging.AsyncLogger.init(allocator, 25000);
defer { logger.stop(); logger.deinit(); }

// Console for development
var console = async_logging.AsyncConsoleHandler.init(allocator, .{
    .fast_mode = false,
    .use_colors = true,
});
defer console.deinit();

// File for production logs
var file_handler = try async_logging.AsyncFileHandler.init(allocator, .{
    .file_path = "logs/production.log",
    .max_file_size = 50 * 1024 * 1024, // 50MB
    .max_files = 10,
    .buffer_size = 16384,
    .flush_interval_ms = 2000,
});
defer file_handler.deinit();

try logger.addHandler(&console.handler);
try logger.addHandler(&file_handler.handler);
try logger.start();

try logger.infoAsync("Production server started");
```

## Performance Notes

- **Queue Size**: Balance memory usage vs. burst capacity
- **Buffer Size**: Larger buffers = better I/O performance, more memory
- **Flush Interval**: Shorter intervals = less data loss risk, more I/O overhead
- **Fast Mode**: Significant performance boost for high-volume logging
- **Backpressure**: Monitor queue stats to prevent message loss

The async logger is designed to handle high-volume logging without blocking your application's main execution path, making it perfect for async runtimes like Zuki.
