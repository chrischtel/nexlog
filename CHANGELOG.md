### v0.6.0 [UNRELEASED] (MMMM DD, YYYY)

#### Added
- Automatic metadata capture helpers
  - New `LogMetadata.create()` function with automatic source location capture using `@src()` builtin
  - Added convenience functions `here()`, `hereWithTimestamp()`, and `hereWithThreadId()` for ergonomic metadata creation
- Comprehensive formatting test example (`formatting_test.zig`)

#### Fixed
- **Fixed automatic metadata capture helpers to show correct caller source location instead of helper definition location**
  - Changed API: `nexlog.here(@src())` instead of `nexlog.here()`
  - Source location now correctly captured from call site, not helper function definition
- **Fixed ISO8601 timestamp formatting producing invalid output like `[+2022-+1-+1T00:00:00Z]` - now correctly generates `[2022-01-01T00:00:00Z]`**
- Hostname placeholder implementation for better cross-platform compatibility

#### Changed
- Enhanced custom formatting system validation
- Verified custom template functionality with user-defined formats
- Confirmed support for multiple level formats (upper, lower, short variants)

### v0.5.0-beta.1 (April 10, 2025)
- Added structured logging support
  - New `StructuredField` and `FieldValue` types for type-safe structured data
  - Enhanced `FormatConfig` to support structured logging formats
  - Added `formatStructured` method to the `Formatter` struct
  - Implemented JSON and logfmt formatting for structured logs
- Added comprehensive examples for structured logging
  - Created `structured_logging.zig` with examples for JSON, logfmt, and custom formats
  - Added `logger_integration.zig` to demonstrate integration with the main logger
  - Fixed memory management in formatter initialization
- Improved error handling in logger convenience methods
  - Enhanced error reporting in `info`, `debug`, `warn`, and `err` methods
  - Added proper error handling for flush operations
- Fixed various compilation and linter errors
  - Resolved unused variable warnings
  - Fixed memory leaks in formatter initialization
  - Improved code organization and readability

### v0.4.0
- fixed segmenation fault on json logging for windows
  - no need to call `defer json_handler.deinit();` anymore since the ownership of the handler is passed to the logger
- reordered memory managment for the json handler
- bug fixes

### v0.3.3 (February 5, 2025)
- improvments
- checking on comptime wethever use zig 0.14 or 0.13 API for handlers.zig

### v0.3.2 (February 5, 2025)
- small improvements

### Fixed v0.3.0 (February 5, 2025)
Added new non-failing log methods for each log level. These methods do not return an error.
fixed compilation errors to support zig 0.14-dev
