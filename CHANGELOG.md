### Fixed
- Fixed deadlock in file rotation when buffer limit is reached
- Fixed memory leaks in file path handling during log rotation
- Improved thread safety for file size tracking
- Added proper memory cleanup for file operations
- Enhanced error recovery during rotation failures

The file handler now properly manages system resources and handles concurrent
access more reliably. Users should see more stable behavior during high-volume
logging with file rotation enabled.