const std = @import("std");
const nexlog = @import("nexlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger with debug level enabled
    const logger = try nexlog.Logger.init(allocator, .{ .min_level = .debug });
    defer logger.deinit();

    std.debug.print("=== Before: Manual Metadata Creation ===\n", .{});

    // OLD WAY: Manual metadata creation (verbose and error-prone)
    const old_metadata = nexlog.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = @as(usize, std.Thread.getCurrentId()),
        .file = @src().file,
        .line = @src().line,
        .function = @src().fn_name,
    };

    try logger.log(.info, "Old way: manual metadata creation", .{}, old_metadata);

    std.debug.print("\n=== After: Automatic Metadata Creation ===\n", .{});

    // NEW WAY: Automatic metadata capture (much cleaner!)
    try logger.log(.info, "New way: automatic metadata capture!", .{}, nexlog.here(@src()));

    // With custom timestamp
    try logger.log(.warn, "Custom timestamp example", .{}, nexlog.hereWithTimestamp(1640995200, @src()));

    // With custom thread ID
    try logger.log(.debug, "Custom thread ID example", .{}, nexlog.hereWithThreadId(12345, @src()));

    // Minimal metadata (no source location)
    try logger.log(.err, "Minimal metadata example", .{}, nexlog.LogMetadata.minimal());

    std.debug.print("\n=== Convenience Methods with Auto-Metadata ===\n", .{});

    // We can also use the convenience methods with automatic metadata
    logger.info("Convenience method with auto-metadata", .{}, nexlog.here(@src()));
    logger.debug("Debug message with auto-metadata", .{}, nexlog.here(@src()));
    logger.warn("Warning with auto-metadata", .{}, nexlog.here(@src()));
    logger.err("Error with auto-metadata", .{}, nexlog.here(@src()));

    try logger.flush();
}
