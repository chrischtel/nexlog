const std = @import("std");
const nexlog = @import("nexlog");
const types = nexlog.core.types;
const handlers = nexlog.output.handler;
const Logger = nexlog.Logger;
// Configuration for the custom handler
pub const CustomConfig = struct {
    min_level: types.LogLevel = .debug,
    prefix: []const u8 = "CUSTOM",
    buffer_size: usize = 4096,
};

// Custom handler that writes to a memory buffer
pub const CustomHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: CustomConfig,
    messages: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, config: CustomConfig) !*Self {
        const handler = try allocator.create(Self);
        handler.* = .{
            .allocator = allocator,
            .config = config,
            .messages = std.ArrayList([]const u8).init(allocator),
        };
        return handler;
    }

    pub fn deinit(self: *Self) void {
        // Free all stored messages
        for (self.messages.items) |msg| {
            self.allocator.free(msg);
        }
        self.messages.deinit();
        self.allocator.destroy(self);
    }

    pub fn log(
        self: *Self,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) !void {
        if (@intFromEnum(level) < @intFromEnum(self.config.min_level)) {
            return;
        }

        // Format the message with prefix and timestamp
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();
        const formatted = try std.fmt.allocPrint(
            self.allocator,
            "[{d}] [{s}] [{s}] {s}",
            .{
                timestamp,
                self.config.prefix,
                level.toString(),
                message,
            },
        );

        // Store the message
        try self.messages.append(formatted);
    }

    pub fn flush(self: *Self) !void {
        // Example: Print all stored messages
        for (self.messages.items) |msg| {
            std.debug.print("{s}\n", .{msg});
        }
    }

    // Get all stored messages
    pub fn getMessages(self: *Self) []const []const u8 {
        return self.messages.items;
    }

    // Clear all stored messages
    pub fn clearMessages(self: *Self) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg);
        }
        self.messages.clearRetainingCapacity();
    }

    /// Convert to generic LogHandler interface
    pub fn toLogHandler(self: *Self) handlers.LogHandler {
        return handlers.LogHandler.init(
            self,
            CustomHandler.log,
            CustomHandler.flush,
            CustomHandler.deinit,
        );
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger instance
    const logger = try Logger.init(allocator, .{});
    defer logger.deinit();

    // Create custom handler with configuration
    var custom_handler = try CustomHandler.init(allocator, .{
        .min_level = .info,
        .prefix = "MY_APP",
    });

    // Add the custom handler to the logger
    try logger.addHandler(custom_handler.toLogHandler());

    // Log some messages
    try logger.log(.info, "Application started", .{}, null);
    try logger.log(.warn, "Low memory warning", .{}, null);
    try logger.log(.err, "Failed to connect", .{}, null);

    // Access the stored messages
    const messages = custom_handler.getMessages();
    std.debug.print("\nStored messages:\n", .{});
    for (messages) |msg| {
        std.debug.print("{s}\n", .{msg});
    }

    // Clear stored messages
    custom_handler.clearMessages();

    // Flush all handlers
    try logger.flush();
}
