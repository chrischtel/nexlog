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
