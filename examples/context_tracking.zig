const std = @import("std");
const nexlog = @import("nexlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize context manager
    nexlog.ContextManager.init(allocator);
    defer nexlog.ContextManager.deinit();

    // Create logger with context-aware template
    const config = nexlog.LogConfig{
        .format_config = .{
            .template = "[{timestamp}] {color}[{level}]{reset} [{request_id}] [{operation}] {function}:{line} - {message}",
            .use_color = true,
        },
    };
    const logger = try nexlog.Logger.init(allocator, config);
    defer logger.deinit();

    // Demo 1: Basic request tracking
    std.debug.print("\n=== Demo 1: Basic Request Tracking ===\n", .{});
    try handleUserRequest(logger, "user123");

    // Demo 2: Cross-function context
    std.debug.print("\n=== Demo 2: Cross-Function Context ===\n", .{});
    try processOrder(logger, "order456");
}

fn handleUserRequest(logger: *nexlog.Logger, user_id: []const u8) !void {
    // Set request context
    nexlog.setRequestContext("req-12345", "user_login");
    defer nexlog.clearContext();

    logger.info("Processing user login for {s}", .{user_id}, nexlog.hereWithContext(@src()));

    try authenticateUser(logger, user_id);
    try loadUserProfile(logger, user_id);

    logger.info("User login completed successfully", .{}, nexlog.hereWithContext(@src()));
}

fn authenticateUser(logger: *nexlog.Logger, user_id: []const u8) !void {
    logger.debug("Validating credentials for user {s}", .{user_id}, nexlog.hereWithContext(@src()));
    // Simulate auth work
    std.Thread.sleep(10 * 1000000); // 10ms
    logger.debug("Credentials validated", .{}, nexlog.hereWithContext(@src()));
}

fn loadUserProfile(logger: *nexlog.Logger, user_id: []const u8) !void {
    logger.debug("Loading profile for user {s}", .{user_id}, nexlog.hereWithContext(@src()));
    // Simulate database work
    std.Thread.sleep(20 * 1000000); // 20ms
    logger.debug("Profile loaded", .{}, nexlog.hereWithContext(@src()));
}

fn processOrder(logger: *nexlog.Logger, order_id: []const u8) !void {
    // Set different request context
    nexlog.setRequestContext("req-67890", "order_processing");
    defer nexlog.clearContext();

    logger.info("Processing order {s}", .{order_id}, nexlog.hereWithContext(@src()));

    // Add correlation for external service call
    nexlog.correlate("corr-abc123");
    logger.info("Calling payment service", .{}, nexlog.hereWithContext(@src()));

    try validatePayment(logger, order_id);
    try updateInventory(logger, order_id);

    logger.info("Order processed successfully", .{}, nexlog.hereWithContext(@src()));
}

fn validatePayment(logger: *nexlog.Logger, order_id: []const u8) !void {
    logger.debug("Validating payment for order {s}", .{order_id}, nexlog.hereWithContext(@src()));
    // All logs here will have the request context AND correlation ID
    logger.debug("Payment validation complete", .{}, nexlog.hereWithContext(@src()));
}

fn updateInventory(logger: *nexlog.Logger, order_id: []const u8) !void {
    logger.debug("Updating inventory for order {s}", .{order_id}, nexlog.hereWithContext(@src()));
    logger.debug("Inventory updated", .{}, nexlog.hereWithContext(@src()));
}
