# nexlog <br/> Test Change

<!-- Space for transparent logo -->
<div align="center">
  <!-- Logo will go here -->
<img src="docs/logo.png" alt="nexlog" width="200" height="200">
</div>

A powerful, fast, and beautifully simple logging library for Zig applications. Built from the ground up to handle everything from quick debugging to production-scale logging with grace.

[![Latest Release](https://img.shields.io/github/v/release/awacsm81/nexlog?include_prereleases&sort=semver)](https://github.com/awacsm81/nexlog/releases)
[![Performance](https://img.shields.io/badge/Performance-40K%20logs%2Fs-brightgreen)](https://github.com/chrischtel/nexlog#benchmarks)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

---

*Currently in active development - check the [CHANGELOG](./CHANGELOG.md) for the latest updates*

**Compatible with Zig 0.14 and 0.15.0-dev.877+0adcfd60f**

> [!WARNING]  
> Zig v0.15.1 dropped gzip compression support in the standard library. Coming with the next update, compressing rotated files with gzip will be unavailable. For further information, follow [this issue](https://github.com/chrischtel/nexlog/issues/40).

## Why nexlog?  

After working with logging libraries across different languages, I found myself constantly missing features or fighting with overly complex APIs. nexlog was born from the simple idea that logging should be powerful when you need it, but never get in your way when you don't.

Whether you're debugging a quick script or building a distributed system that needs to track requests across services, nexlog scales with your needs.

## Features

**Core Logging**
- Multiple log levels with beautiful colored output
- Automatic source location tracking (file, line, function)
- Rich metadata support with timestamps and thread IDs
- Zero-overhead when logging is disabled

**Advanced Features**
- Context tracking for following requests across your application
- Structured logging with JSON, logfmt, and custom formats
- Automatic file rotation with configurable size limits
- Custom handlers for sending logs anywhere
- High-performance async mode for demanding applications
- Type-safe API with full Zig compile-time guarantees

## Installation

Add nexlog to your `build.zig.zon` file:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .nexlog = .{
            .url = "git+https://github.com/chrischtel/nexlog/",
            .hash = "...", // Run `zig fetch` to get the hash
        },
    },
}
```

**Quick install:**
```bash
zig fetch --save git+https://github.com/chrischtel/nexlog/
```

*For development versions, append `#develop` to the URL.*

## Quick Start

Get up and running in three lines:

```zig
const std = @import("std");
const nexlog = @import("nexlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger with minimal configuration
    const logger = try nexlog.Logger.init(allocator, .{});
    defer logger.deinit();

    // Start logging with automatic source location tracking
    logger.info("Application starting", .{}, nexlog.here(@src()));
    logger.debug("Initializing subsystems", .{}, nexlog.here(@src()));
    logger.warn("Resource usage high", .{}, nexlog.here(@src()));
    logger.info("Application shutdown complete", .{}, nexlog.here(@src()));
}
```

## Real-World Examples

### Context Tracking for Request Flows

Track user requests as they flow through your application. Perfect for debugging distributed systems or complex request handling:

```zig
// Set request context once at the entry point
nexlog.setRequestContext("req-12345", "user_login");
defer nexlog.clearContext();

logger.info("Processing user login for {s}", .{user_id}, nexlog.hereWithContext(@src()));

// All subsequent logs automatically include request context
try authenticateUser(logger, user_id);
try loadUserProfile(logger, user_id);

logger.info("User login completed successfully", .{}, nexlog.hereWithContext(@src()));
```

### Structured Logging for Analytics

When you need machine-readable logs for monitoring and analytics:

```zig
// Configure formatter for JSON output
const config = format.FormatConfig{
    .structured_format = .json,
    .include_timestamp_in_structured = true,
    .include_level_in_structured = true,
};

var formatter = try format.Formatter.init(allocator, config);
defer formatter.deinit();

// Create structured fields for rich context
const fields = [_]format.StructuredField{
    .{ .name = "user_id", .value = "12345", .attributes = null },
    .{ .name = "request_duration_ms", .value = "150", .attributes = null },
    .{ .name = "endpoint", .value = "/api/login", .attributes = null },
};

logger.info("API request completed", .{}, &fields);
```

### Smart File Rotation

Never worry about log files filling up your disk:

```zig
var builder = nexlog.LogBuilder.init();
try builder
    .setMinLevel(.debug)
    .enableFileLogging(true, "logs/app.log")
    .setMaxFileSize(10 * 1024 * 1024)  // 10MB per file
    .setMaxRotatedFiles(5)             // Keep 5 backup files
    .enableRotation(true)
    .build(allocator);

// Automatically creates: app.log, app.log.1, app.log.2, etc.
```

### Custom Handlers for Specialized Needs

Send logs to external services, databases, or custom destinations:

```zig
pub const CustomHandler = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) !*@This() {
        const handler = try allocator.create(@This());
        handler.* = .{
            .allocator = allocator,
            .messages = std.ArrayList([]const u8).init(allocator),
        };
        return handler;
    }

    pub fn log(self: *@This(), level: LogLevel, message: []const u8, metadata: LogMetadata) !void {
        // Custom logic: store, forward, filter, transform, etc.
        const stored_message = try self.allocator.dupe(u8, message);
        try self.messages.append(stored_message);
    }
};
```

## Performance That Matters

Recent benchmarks show nexlog handles high-throughput scenarios gracefully:

| Scenario | Logs/Second | Notes |
|----------|-------------|-------|
| Simple console logging | 41,297 | Basic text output |
| JSON structured logging | 26,790 | Full structured format |
| Logfmt output | 39,284 | Key-value format |
| Large payloads (100 fields) | 8,594 | Complex structured data |
| Production integration | 5,878 | Full pipeline with handlers |

Run the benchmarks yourself:
```bash
zig build bench
```

## Configuration

Configure nexlog to fit your specific needs:

```zig
var builder = nexlog.LogBuilder.init();
try builder
    .setMinLevel(.debug)
    .enableColors(true)
    .setBufferSize(8192)
    .enableFileLogging(true, "logs/app.log")
    .setMaxFileSize(5 * 1024 * 1024)
    .setMaxRotatedFiles(3)
    .enableRotation(true)
    .enableAsyncMode(true)
    .build(allocator);
```

## Learning More

The `examples/` directory contains working code for every feature:

- **`basic_usage.zig`** - Start here for simple logging
- **`context_tracking.zig`** - Request tracking across functions  
- **`structured_logging.zig`** - JSON, logfmt, and custom formats
- **`file_rotation.zig`** - Automatic file management
- **`custom_handler.zig`** - Build your own log destinations
- **`json_logging.zig`** - Optimized JSON output
- **`benchmark.zig`** - Performance testing and optimization
- **`time_travel.zig`** - Advanced debugging features
- **`visualization.zig`** - Log analysis and visualization

## Contributing

I welcome contributions of all kinds. Whether it's fixing bugs, adding features, improving documentation, or sharing how you use nexlog in your projects.

Before starting work on a major feature, please open an issue to discuss the approach. This helps ensure your effort aligns with the project's direction and avoids duplicate work.

## License

nexlog is available under the MIT License. See the [LICENSE](./LICENSE) file for the complete text.

---

