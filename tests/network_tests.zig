const std = @import("std");
const expect = std.testing.expect;
const NetworkHandler = @import("nexlog").output.network.NetworkHandler;
const NetworkConfig = @import("nexlog").output.network.NetworkConfig;

test "NetworkHandler initialization and deinitialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const config = NetworkConfig{
        .endpoint = .{
            .host = "example.com",
            .port = 8080,
            .secure = true,
        },
    };

    var handler = try NetworkHandler.init(allocator, config);
    defer handler.deinit();

    try expect(handler.config.endpoint.host.len == config.endpoint.host.len);
    try expect(handler.config.endpoint.port == config.endpoint.port);
    try expect(handler.circular_buffer.buffer.len == config.buffer_size);

    std.debug.print("NetworkHandler initialized\n", .{});
}
