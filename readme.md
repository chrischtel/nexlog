# nexlog

**nexlog** is a high-performance, flexible, and feature-rich logging library for Zig applications. Designed with both power and ease-of-use in mind, nexlog offers asynchronous logging, file rotation, structured logging, and much more — making it a perfect fit for projects of any size.

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Advanced Configuration](#advanced-configuration)
- [Custom Handlers](#custom-handlers)
- [JSON Logging](#json-logging)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Multiple Log Levels**: Supports debug, info, warning, and error levels.
- **Asynchronous Logging**: High-performance async mode minimizes the impact on application performance.
- **File Rotation**: Automatically rotates log files based on configurable file sizes and backup counts.
- **Customizable Handlers**: Comes with built-in handlers for console, file, and JSON outputs; also supports custom handlers.
- **Rich Metadata**: Automatically includes timestamps, thread IDs, file names, and function names.
- **Structured Logging**: Provides JSON output for machine-readable logs.
- **Color Support**: Terminal color coding for different log levels enhances readability.
- **Configurable Buffer Size**: Adjustable buffer size for optimal performance.
- **Context-Based Logging**: Supports department- or component-specific logging contexts.

---

## Installation

Add **nexlog** as a dependency in your `build.zig.zon` file.

### Fetching from GitHub

```bash
zig fetch --save git+https://github.com/chrischtel/nexlog/
```

In your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .nexlog = .{
            // 🚧 Nexlog: Actively Developing
            // Expect rapid feature growth and frequent changes.
            // To fetch the develop branch, append `#develop` to the URL.
            .url = "git+https://github.com/chrischtel/nexlog/",
            .hash = "...",
        },
    },
}
```

> **Tip:** To fetch a specific release of **nexlog**, use:
>
> ```bash
> zig fetch --save https://github.com/chrischtel/nexlog/archive/v0.4.0.tar.gz
> ```
>
> Replace `v0.4.0` with your desired release version.

---

## Quick Start

Below is a basic example to help you get started:

```zig
const std = @import("std");
const nexlog = @import("nexlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger with basic configuration
    var builder = nexlog.LogBuilder.init();
    try builder
        .setMinLevel(.debug)
        .enableColors(true)
        .enableFileLogging(true, "logs/app.log")
        .build(allocator);
    defer nexlog.deinit();

    // Get the default logger
    const logger = nexlog.getDefaultLogger() orelse return error.LoggerNotInitialized;

    // Log some messages
    logger.info("Application starting", .{}, null);
    logger.debug("Debug information", .{}, null);
    logger.warn("Warning message", .{}, null);
    logger.err("Error occurred", .{}, null);
}
```

---

## Advanced Configuration

nexlog's builder pattern makes advanced configuration straightforward:

```zig
try builder
    .setMinLevel(.debug)
    .enableColors(true)
    .setBufferSize(8192)
    .enableFileLogging(true, "logs/app.log")
    .setMaxFileSize(5 * 1024 * 1024)  // 5MB
    .setMaxRotatedFiles(3)
    .enableRotation(true)
    .enableAsyncMode(true)
    .enableMetadata(true)
    .build(allocator);
```

This configuration sets up a logger with:

- A minimum log level of debug.
- Color support enabled.
- Custom buffer size.
- File logging with rotation parameters.
- Asynchronous logging and metadata inclusion.

---

## Custom Handlers

Need specialized logging? Create your own log handler. Here's a simple scaffold:

```zig
const CustomHandler = struct {
    // Implement custom handling logic here.
};
```

For more details, see the [Custom Handlers Documentation](#).

---

## JSON Logging

For structured, machine-readable logs, nexlog provides built-in JSON support:

```zig
var json_handler = try JsonHandler.init(allocator, .{
    .min_level = .debug,
    .pretty_print = true,
    .output_file = "logs/app.json",
});
```

This configuration writes prettified JSON logs to `logs/app.json`, starting at the debug level.

---

## Documentation

For more detailed information, check out the following resources:

- [Configuration Guide](#)
- [Handler Documentation](#)
- [Advanced Usage Examples](#)
- [API Reference](#)

---

## Contributing

Contributions are welcome! If you'd like to contribute:

1. Fork the repository.
2. Create a new branch for your feature or bug fix.
3. Commit your changes.
4. Open a Pull Request.

For major changes, please open an issue first to discuss what you would like to change.

---

## License

This project is licensed under the BSD 3-Clause License. See the [LICENSE](./LICENSE) file for more details.
---

Happy logging with **nexlog**!
