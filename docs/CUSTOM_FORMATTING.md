# Custom Formatting

NexLog provides flexible formatting options to customize how your logs appear. You can use built-in templates or create your own.

## Template Placeholders

Available placeholders for log templates:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{timestamp}` | Unix timestamp | `1640995200` |
| `{level}` | Log level | `INFO` |
| `{message}` | Log message | `User logged in` |
| `{file}` | Source file name | `main.zig` |
| `{line}` | Source line number | `42` |
| `{function}` | Function name | `handleRequest` |
| `{thread_id}` | Thread identifier | `12345` |
| `{hostname}` | System hostname | `server-01` |

## Default Templates

NexLog comes with several built-in templates:

### Standard Format
```
{timestamp} [{level}] [{file}:{line}] {message}
```
Output: `1640995200 [INFO] [main.zig:42] Application started`

### Compact Format
```
{level}: {message}
```
Output: `INFO: Application started`

### Detailed Format
```
{timestamp} [{level}] {hostname} {function}() {file}:{line} - {message}
```
Output: `1640995200 [INFO] server-01 main() main.zig:42 - Application started`

## Custom Templates

Define your own log format:

```zig
const config = nexlog.LogConfig{
    .custom_template = "[{level}] {message} (from {function})",
};
```

Output: `[INFO] User logged in (from handleLogin)`

## Timestamp Formats

Configure timestamp display:

```zig
const config = nexlog.LogConfig{
    .timestamp_format = .iso8601, // ISO8601 format
    // or .unix for Unix timestamp (default)
};
```

ISO8601 output: `[2022-01-01T00:00:00Z] [INFO] Application started`

## Log Level Formats

Customize how log levels appear:

```zig
const config = nexlog.LogConfig{
    .level_format = .upper, // INFO, WARN, ERROR
    // .lower,              // info, warn, error  
    // .short_upper,        // INF, WRN, ERR
    // .short_lower,        // inf, wrn, err
};
```

## Colors

Enable colored output for better readability:

```zig
const config = nexlog.LogConfig{
    .enable_colors = true,
    .color_scheme = .default, // or .dark, .light
};
```

Color mapping:
- TRACE: Gray
- DEBUG: Cyan  
- INFO: Green
- WARN: Yellow
- ERROR: Red
- CRITICAL: Bright Red

## Advanced Formatting

### Conditional Formatting

Some placeholders are optional and won't appear if data is unavailable:

```zig
// If no metadata provided, file/line/function won't show
const template = "{timestamp} [{level}] {file?}:{line?} {message}";
```

### Field Width and Alignment

Control field appearance:

```zig
// Right-align level in 8 characters
const template = "{timestamp} [{level:>8}] {message}";
```

Output: `1640995200 [    INFO] Application started`

### Escaping

Use double braces to include literal braces:

```zig
const template = "{{level}}: {message}"; 
```

Output: `{level}: Application started`

## JSON Formatting

For structured output, enable JSON formatting:

```zig
const config = nexlog.LogConfig{
    .output_format = .json,
    .include_metadata = true,
};
```

Output:
```json
{"timestamp":1640995200,"level":"INFO","file":"main.zig","line":42,"message":"Application started"}
```

## Performance Considerations

- Simple templates are faster than complex ones
- Avoid expensive placeholders like `{hostname}` in high-frequency logs
- Use buffered output for better performance
- Consider disabling colors in production

## Template Validation

NexLog validates templates at initialization:

```zig
// This will return an error
const bad_config = nexlog.LogConfig{
    .custom_template = "{invalid_placeholder} {message}",
};
const logger = nexlog.Logger.init(allocator, bad_config); // Error!
```

## Examples

### Web Server Logs
```zig
const template = "{timestamp} [{level}] {method} {url} {status_code} {response_time}ms";
```

### Debug Logs
```zig  
const template = "[{level}] {function}() at {file}:{line} - {message}";
```

### Production Logs
```zig
const template = "{timestamp} {level} {message}";
```
