// const std = @import("std");
// const testing = std.testing;
// const JsonHandler = @import("nexlog").output.json_handler.JsonHandler;
// const LogLevel = @import("nexlog").LogLevel;
// const LogMetadata = @import("nexlog").LogMetadata;

// test "JsonHandler basic initialization" {
//     const allocator = testing.allocator;
//     var handler = try JsonHandler.init(allocator, .{});
//     try handler.log(.info, "Test initialization", null);
//     try handler.flush();
//     handler.deinit();
// }

// test "JsonHandler log message" {
//     const allocator = testing.allocator;
//     var handler = try JsonHandler.init(allocator, .{});
//     defer handler.deinit();

//     const metadata = LogMetadata{
//         .timestamp = 1234567890,
//         .thread_id = 1,
//         .file = "test.zig",
//         .line = 42,
//         .function = "testFunc",
//     };

//     try handler.log(.info, "Test message", metadata);
//     try handler.flush();
// }

// test "JsonHandler file output" {
//     const allocator = testing.allocator;
//     var tmp_dir = testing.tmpDir(.{});
//     defer tmp_dir.cleanup();

//     // Create temporary file path
//     const test_path = try std.fs.path.join(
//         allocator,
//         &[_][]const u8{ tmp_dir.dir.realpath(".", &[_]u8{}) catch unreachable, "test.json" },
//     );
//     defer allocator.free(test_path);

//     // Initialize handler
//     var handler = try JsonHandler.init(allocator, .{
//         .output_file = test_path,
//     });

//     // Write test logs
//     try handler.log(.info, "Test message 1", null);
//     try handler.log(.warn, "Test message 2", null);
//     try handler.flush();

//     // Read and verify file contents
//     const file = try tmp_dir.dir.openFile("test.json", .{ .mode = .read_only });
//     defer file.close();

//     const file_contents = try file.readToEndAlloc(allocator, 1024 * 1024);
//     defer allocator.free(file_contents);

//     // Basic verification
//     try testing.expect(std.mem.indexOf(u8, file_contents, "Test message 1") != null);
//     try testing.expect(std.mem.indexOf(u8, file_contents, "Test message 2") != null);

//     // Cleanup
//     handler.deinit();
// }

// test "JsonHandler as generic LogHandler" {
//     const allocator = testing.allocator;
//     var json_handler = try JsonHandler.init(allocator, .{});
//     const log_handler = json_handler.toLogHandler();

//     try log_handler.writeLog(.info, "Test generic handler", null);
//     try log_handler.flush();
//     log_handler.deinit();
// }
