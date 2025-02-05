const std = @import("std");
const nexlog = @import("nexlog");
const JsonHandler = nexlog.output.json_handler.JsonHandler;

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a directory for testing logs if it doesn't exist
    const log_dir = "test_logs";
    try std.fs.cwd().makePath(log_dir);

    // Get the current working directory
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch unreachable;

    // Construct the absolute path for the log file within the log_dir
    const log_file_path = std.fs.path.join(allocator, &[_][]const u8{ cwd, log_dir, "app.json" }) catch unreachable;
    defer allocator.free(log_file_path);

    // Create a JSON handler
    var json_handler = try JsonHandler.init(allocator, .{
        .min_level = .debug,
        .pretty_print = true, // Optional: Makes the JSON output more readable
        .output_file = log_file_path,
    });

    // Create a logger
    const logger = try nexlog.Logger.init(allocator, .{});
    defer logger.deinit();

    // Add the JSON handler to the logger
    try logger.addHandler(json_handler.toLogHandler());

    // Create some basic metadata
    const metadata = nexlog.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 0, // Replace with actual thread ID in a real application
        .file = @src().file,
        .line = @src().line,
        .function = @src().fn_name,
    };

    // Log some messages with different levels and optional fields
    // Log some messages with different levels and optional fields
    try logger.log(.info, "Application starting", .{}, metadata);
    try logger.log(.debug, "This is a debug message", .{}, metadata);
    try logger.log(.warn, "This is a warning message (code: {d})", .{123}, metadata);
    try logger.log(.err, "An error occurred (code: {s})", .{"E_UNKNOWN"}, metadata);

    // Ensure all logs are written before exiting
    try logger.flush();
}
