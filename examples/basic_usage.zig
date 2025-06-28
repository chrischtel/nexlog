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
