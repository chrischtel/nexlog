const std = @import("std");
const nexlog = @import("nexlog");

/// Example struct to demonstrate context-based logging
const OrderProcessor = struct {
    logger: *nexlog.Logger,
    department: []const u8,

    pub fn init(logger: *nexlog.Logger, department: []const u8) OrderProcessor {
        return .{
            .logger = logger,
            .department = department,
        };
    }

    // Keep it as a member function with self parameter
    fn createMetadata(self: *const OrderProcessor) nexlog.LogMetadata {
        _ = self; // Tell Zig we're intentionally not using self for now
        return .{
            .timestamp = std.time.timestamp(),
            .thread_id = 0, // In a real app, get actual thread ID
            .file = @src().file,
            .line = @src().line,
            .function = @src().fn_name,
        };
    }

    pub fn processOrder(self: *const OrderProcessor, order_id: u32) !void {
        const metadata = self.createMetadata();

        // Log the start of order processing
        try self.logger.log(.debug, "Starting order processing [dept={s}, order_id={d}]", .{ self.department, order_id }, metadata);

        // Simulate processing steps with appropriate logging
        try self.validateOrder(order_id);
        try self.processPayment(order_id);
        try self.finalizeOrder(order_id);
    }

    fn validateOrder(self: *const OrderProcessor, order_id: u32) !void {
        const metadata = self.createMetadata();
        try self.logger.log(.debug, "Validating order {d}", .{order_id}, metadata);

        // Demonstrate warning logs for specific conditions
        if (order_id % 3 == 0) {
            try self.logger.log(.warn, "Order {d} requires manual review - high value order", .{order_id}, metadata);
        }
    }

    fn processPayment(self: *const OrderProcessor, order_id: u32) !void {
        const metadata = self.createMetadata();
        try self.logger.log(.info, "Processing payment for order {d}", .{order_id}, metadata);

        // Demonstrate error logging
        if (order_id % 5 == 0) {
            try self.logger.log(.err, "Payment processing failed for order {d} - retry scheduled", .{order_id}, metadata);
        }
    }

    fn finalizeOrder(self: *const OrderProcessor, order_id: u32) !void {
        const metadata = self.createMetadata();
        try self.logger.log(.info, "Order {d} processed successfully", .{order_id}, metadata);
    }
};

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logs directory if it doesn't exist
    try std.fs.cwd().makePath("logs");

    var builder = nexlog.LogBuilder.init();
    try builder
        .setMinLevel(.debug)
        .enableColors(true)
        .setBufferSize(8192)
        .enableFileLogging(true, "logs/app.log")
        .setMaxFileSize(5 * 1024 * 1024)
        .setMaxRotatedFiles(3)
        .enableRotation(true)
        .enableAsyncMode(true)
        .enableMetadata(true)
        .build(allocator);
    defer nexlog.deinit();

    // Get the default logger
    const logger = nexlog.getDefaultLogger() orelse return error.LoggerNotInitialized;

    // Create base metadata for general logging
    const base_metadata = nexlog.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 0,
        .file = @src().file,
        .line = @src().line,
        .function = @src().fn_name,
    };

    // Log application startup
    try logger.log(.info, "Application starting", .{}, base_metadata);

    // Simulate some logging activity
    try logger.log(.debug, "Initializing subsystems", .{}, base_metadata);
    try logger.log(.info, "Processing started", .{}, base_metadata);
    try logger.log(.warn, "Resource usage high", .{}, base_metadata);

    // Ensure all logs are written before shutdown
    try logger.flush();
    try logger.log(.info, "Application shutdown complete", .{}, base_metadata);
}
