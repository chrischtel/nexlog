# nexlog

**nexlog** is a high-performance, flexible, and feature-rich logging library for Zig applications. Designed with both power and ease-of-use in mind, nexlog offers asynchronous logging, file rotation, structured logging, and much more — making it a perfect fit for projects of any size.
[![Latest Release](https://img.shields.io/github/v/release/awacsm81/nexlog?include_prereleases&sort=semver)](https://github.com/awacsm81/nexlog/releases)
[![Benchmark Results](https://img.shields.io/badge/Performance-40K%20logs%2Fs-brightgreen)](https://github.com/chrischtel/nexlog#benchmarks)
[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](./LICENSE)

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Examples](#examples)
- [Advanced Features](#advanced-features)
  - [Structured Logging](#structured-logging)
  - [File Rotation](#file-rotation)
  - [Custom Handlers](#custom-handlers)
  - [JSON Logging](#json-logging)
  - [Context Tracking](#context-tracking)
- [Configuration](#configuration)
- [Benchmarks](#benchmarks)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Multiple Log Levels**: Supports debug, info, warning, and error levels
- **Asynchronous Logging**: High-performance async mode minimizes impact on application performance
- **File Rotation**: Automatic log file rotation with configurable size and backup counts
- **Structured Logging**: Multiple output formats (JSON, logfmt, custom) for machine-readable logs
- **Rich Metadata**: Automatic inclusion of timestamps, thread IDs, file names, and function names
- **Custom Handlers**: Built-in handlers for console, file, and JSON outputs; extensible for custom needs
- **Color Support**: Terminal color coding for different log levels
- **Configurable Buffer Size**: Adjustable buffer size for optimal performance
- **Context Tracking**: Support for department- or component-specific logging contexts
- **High Performance**: Benchmarked at 40K+ logs per second
- **Type Safety**: Full Zig type safety and compile-time checks

---

## Installation

Add **nexlog** as a dependency in your `build.zig.zon` file:

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

### Quick Install

```bash
zig fetch --save git+https://github.com/chrischtel/nexlog/
```

> **Note:** For development versions, append `#develop` to the URL.

---

## Quick Start

Here's a simple example to get you started:

```zig
const std = @import("std");
const nexlog = @import("nexlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simple logger initialization with minimal config
    const logger = try nexlog.Logger.init(allocator, .{});
    defer logger.deinit();

    // Basic logging - this is what most users want
    logger.info("Application starting", .{}, nexlog.here(@src()));
    logger.debug("Initializing subsystems", .{}, nexlog.here(@src()));
    logger.info("Processing started", .{}, nexlog.here(@src()));
    logger.warn("Resource usage high", .{}, nexlog.here(@src()));
    logger.info("Application shutdown complete", .{}, nexlog.here(@src()));
}
```
---

## Examples

The `examples/` directory contains comprehensive examples for all features:

- `basic_usage.zig`: Simple logging setup and usage
- `structured_logging.zig`: Advanced structured logging with JSON and logfmt
- `file_rotation.zig`: File rotation configuration and management
- `custom_handler.zig`: Creating custom log handlers
- `json_logging.zig`: JSON-specific logging features
- `logger_integration.zig`: Integrating with existing applications
- `benchmark.zig`: Performance benchmarking examples

### Structured Logging Example

```zig
const fields = [_]nexlog.StructuredField{
    .{
        .name = "user_id",
        .value = "12345",
    },
    .{
        .name = "action",
        .value = "login",
    },
};

logger.info("User logged in", .{}, &fields);
```

### File Rotation Example

```zig
try builder
    .enableFileLogging(true, "logs/app.log")
    .setMaxFileSize(5 * 1024 * 1024)  // 5MB
    .setMaxRotatedFiles(3)
    .enableRotation(true)
    .build(allocator);
```

---

## Advanced Features

### Structured Logging

nexlog supports multiple structured logging formats:

1. **JSON Format**
   ```json
   {
     "timestamp": "2024-03-19T10:42:00Z",
     "level": "info",
     "message": "User logged in",
     "fields": {
       "user_id": "12345",
       "action": "login"
     }
   }
   ```

2. **Logfmt Format**
   ```
   timestamp=2024-03-19T10:42:00Z level=info message="User logged in" user_id=12345 action=login
   ```

3. **Custom Format**
   ```
   [2024-03-19T10:42:00Z] INFO | User logged in | user_id=12345 | action=login
   ```

### File Rotation

Configure file rotation with size limits and backup counts:

```zig
try builder
    .enableFileLogging(true, "logs/app.log")
    .setMaxFileSize(5 * 1024 * 1024)  // 5MB
    .setMaxRotatedFiles(3)
    .enableRotation(true)
    .build(allocator);
```

This creates rotated files like:
- `app.log`
- `app.log.1`
- `app.log.2`
- `app.log.3`

### Custom Handlers

Create custom log handlers for specialized needs:

```zig
const CustomHandler = struct {
    pub fn handle(level: nexlog.LogLevel, message: []const u8, fields: ?[]const nexlog.StructuredField) !void {
        // Custom handling logic
    }
};
```

---

## Configuration

Advanced configuration using the builder pattern:

```zig
try builder
    .setMinLevel(.debug)
    .enableColors(true)
    .setBufferSize(8192)
    .enableFileLogging(true, "logs/app.log")
    .setMaxFileSize(5 * 1024 * 1024)
    .setMaxRotatedFiles(3)
    .enableRotation(true)
    .enableAsyncMode(true)
    .enableMetadata(true)
    .build(allocator);
```

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `minLevel` | Minimum log level to process | `.info` |
| `bufferSize` | Size of the log buffer | `4096` |
| `maxFileSize` | Maximum size before rotation | `10MB` |
| `maxRotatedFiles` | Number of backup files to keep | `5` |
| `asyncMode` | Enable asynchronous logging | `false` |
| `colors` | Enable terminal colors | `true` |
| `metadata` | Include metadata in logs | `true` |

---

## Benchmarks

Recent benchmark results (Windows, Release mode):

| Format | Logs/Second | Notes |
|--------|-------------|-------|
| JSON | 26,790 | Base structured format |
| Logfmt | 39,284 | ~47% faster than JSON |
| Custom | 41,297 | Fastest format |
| Large Fields | 8,594 | With 100-field JSON payload |
| Many Fields | 7,333 | With 50 separate fields |
| With Attributes | 20,776 | Including field attributes |
| Full Integration | 5,878 | Complete logging pipeline |

Run benchmarks with:
```bash
zig build bench
```

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Open a Pull Request

For major changes, please open an issue first to discuss your ideas.

---

## License

This project is licensed under the BSD 3-Clause License. See the [LICENSE](./LICENSE) file for details.

---

Happy logging with **nexlog**! 🚀
