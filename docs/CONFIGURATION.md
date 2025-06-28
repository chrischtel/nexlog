# Configuration Reference

Complete reference for configuring NexLog.

## LogConfig

Main configuration structure for initializing loggers.

```zig
const config = nexlog.LogConfig{
    // Basic settings
    .min_level = .info,
    .enable_colors = true,
    .output_format = .standard,
    
    // File logging
    .enable_file_logging = false,
    .file_path = "app.log",
    .max_file_size = 10 * 1024 * 1024,
    .max_file_count = 5,
    
    // Performance
    .buffer_size = 8 * 1024,
    .flush_interval_ms = 5000,
    
    // Formatting
    .custom_template = null,
    .timestamp_format = .unix,
    .level_format = .upper,
    .include_metadata = true,
};
```

## Basic Settings

### min_level
**Type:** `LogLevel`  
**Default:** `.info`  
**Description:** Minimum log level to output. Messages below this level are ignored.

```zig
.min_level = .debug, // Log debug and above
.min_level = .warn,  // Only warnings and errors
```

### enable_colors
**Type:** `bool`  
**Default:** `true`  
**Description:** Enable colored output in console logs.

```zig
.enable_colors = true,  // Colored output
.enable_colors = false, // Plain text
```

### output_format
**Type:** `OutputFormat`  
**Default:** `.standard`  
**Options:** `.standard`, `.json`, `.compact`, `.custom`

```zig
.output_format = .json,     // JSON structured logs
.output_format = .compact,  // Minimal format
.output_format = .custom,   // Use custom_template
```

## File Logging

### enable_file_logging
**Type:** `bool`  
**Default:** `false`  
**Description:** Enable logging to file in addition to console.

### file_path
**Type:** `[]const u8`  
**Default:** `"app.log"`  
**Description:** Path where log files will be written.

```zig
.file_path = "logs/application.log",
.file_path = "/var/log/myapp.log",
```

### max_file_size
**Type:** `usize`  
**Default:** `10 * 1024 * 1024` (10MB)  
**Description:** Maximum size before file rotation occurs.

```zig
.max_file_size = 50 * 1024 * 1024, // 50MB
.max_file_size = 1024 * 1024,      // 1MB
```

### max_file_count
**Type:** `usize`  
**Default:** `5`  
**Description:** Number of rotated files to keep.

```zig
.max_file_count = 10, // Keep 10 old files
.max_file_count = 1,  // Keep only current file
```

## Performance Settings

### buffer_size
**Type:** `usize`  
**Default:** `8 * 1024` (8KB)  
**Description:** Internal buffer size for batching log writes.

```zig
.buffer_size = 64 * 1024, // 64KB buffer for high throughput
.buffer_size = 1024,      // 1KB for low memory usage
```

### flush_interval_ms
**Type:** `u64`  
**Default:** `5000` (5 seconds)  
**Description:** How often to flush buffered logs to disk.

```zig
.flush_interval_ms = 1000, // Flush every second
.flush_interval_ms = 0,    // Flush immediately (no buffering)
```

## Formatting Options

### custom_template
**Type:** `?[]const u8`  
**Default:** `null`  
**Description:** Custom format template. Requires `output_format = .custom`.

```zig
.custom_template = "{timestamp} [{level}] {message}",
.custom_template = "[{level:>5}] {file}:{line} - {message}",
```

### timestamp_format
**Type:** `TimestampFormat`  
**Default:** `.unix`  
**Options:** `.unix`, `.iso8601`

```zig
.timestamp_format = .unix,    // 1640995200
.timestamp_format = .iso8601, // 2022-01-01T00:00:00Z
```

### level_format
**Type:** `LevelFormat`  
**Default:** `.upper`  
**Options:** `.upper`, `.lower`, `.short_upper`, `.short_lower`

```zig
.level_format = .upper,       // INFO, WARN, ERROR
.level_format = .lower,       // info, warn, error
.level_format = .short_upper, // INF, WRN, ERR
.level_format = .short_lower, // inf, wrn, err
```

### include_metadata
**Type:** `bool`  
**Default:** `true`  
**Description:** Include source file, line, and function information.

```zig
.include_metadata = true,  // Show file:line info
.include_metadata = false, // Only timestamp, level, message
```

## Log Levels

Available log levels in order of severity:

```zig
pub const LogLevel = enum {
    trace,    // Most verbose
    debug,    // Debug information
    info,     // General information
    warn,     // Warnings
    err,      // Errors
    critical, // Critical errors
};
```

## Environment Variables

Some settings can be overridden by environment variables:

- `NEXLOG_LEVEL`: Override min_level (`debug`, `info`, `warn`, `error`)
- `NEXLOG_COLOR`: Override enable_colors (`true`, `false`)
- `NEXLOG_FILE`: Override file_path
- `NEXLOG_FORMAT`: Override output_format (`standard`, `json`, `compact`)

## Validation

NexLog validates configuration at initialization:

```zig
// Invalid configurations will return errors
const bad_config = nexlog.LogConfig{
    .max_file_size = 0,           // Error: size must be > 0
    .custom_template = "{bad}",   // Error: unknown placeholder
    .buffer_size = 0,             // Error: buffer must be > 0
};

const logger = nexlog.Logger.init(allocator, bad_config) catch |err| {
    // Handle configuration error
    std.debug.print("Config error: {}\n", .{err});
    return;
};
```

## Performance Recommendations

### High Throughput Applications
```zig
const config = nexlog.LogConfig{
    .min_level = .warn,           // Reduce log volume
    .buffer_size = 64 * 1024,     // Large buffer
    .flush_interval_ms = 1000,    // Less frequent flushes
    .enable_colors = false,       // Skip color processing
    .include_metadata = false,    // Minimal formatting
};
```

### Development
```zig
const config = nexlog.LogConfig{
    .min_level = .debug,          // Verbose logging
    .enable_colors = true,        // Readable output
    .include_metadata = true,     // Full context
    .flush_interval_ms = 0,       // Immediate output
};
```

### Production
```zig
const config = nexlog.LogConfig{
    .min_level = .info,
    .output_format = .json,       // Structured for aggregation
    .enable_file_logging = true,  // Persistent logs
    .max_file_size = 100 * 1024 * 1024, // 100MB files
    .enable_colors = false,       // No colors in files
};
```
