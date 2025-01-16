// tests/pattern_tests.zig
const std = @import("std");
const testing = std.testing;
const nexlog = @import("nexlog");
const types = nexlog.core.types;
test "pattern: basic type detection" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    const err_pattern = try analyzer.analyzeMessage("Connection error occurred");
    try testing.expect(err_pattern != null);
    try testing.expectEqual(nexlog.PatternType.err, err_pattern.?.pattern_type);

    const metric_pattern = try analyzer.analyzeMessage("CPU usage metric: 85%");
    try testing.expect(metric_pattern != null);
    try testing.expectEqual(nexlog.PatternType.metric, metric_pattern.?.pattern_type);

    const event_pattern = try analyzer.analyzeMessage("System startup event");
    try testing.expect(event_pattern != null);
    try testing.expectEqual(nexlog.PatternType.event, event_pattern.?.pattern_type);
}

test "pattern: similarity matching" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    // Test similar messages
    const msg1 = "User admin logged in from 192.168.1.1";
    const msg2 = "User john logged in from 192.168.1.2";

    const pattern1 = try analyzer.analyzeMessage(msg1);
    try testing.expect(pattern1 != null);

    const pattern2 = try analyzer.analyzeMessage(msg2);
    try testing.expect(pattern2 != null);

    // Should detect these as the same pattern
    try testing.expectEqual(pattern1.?.hash, pattern2.?.hash);
}

test "pattern: variable detection" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    // Test number variable
    const msg_number = "Process used 1234 MB of memory";
    const pattern_number = try analyzer.analyzeMessage(msg_number);
    try testing.expect(pattern_number != null);
    try testing.expect(pattern_number.?.variables.items.len > 0);
    try testing.expectEqual(nexlog.VarType.number, pattern_number.?.variables.items[0].var_type);

    // Test IP address variable
    const msg_ip = "Connection from 192.168.1.1";
    const pattern_ip = try analyzer.analyzeMessage(msg_ip);
    try testing.expect(pattern_ip != null);
    try testing.expect(pattern_ip.?.variables.items.len > 0);
    try testing.expectEqual(nexlog.VarType.ip_address, pattern_ip.?.variables.items[0].var_type);

    // Test email variable
    const msg_email = "Email received from test@example.com";
    const pattern_email = try analyzer.analyzeMessage(msg_email);
    try testing.expect(pattern_email != null);
    try testing.expect(pattern_email.?.variables.items.len > 0);
    try testing.expectEqual(nexlog.VarType.email, pattern_email.?.variables.items[0].var_type);
}

test "pattern: cleanup and limits" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{
        .max_patterns = 2,
        .max_pattern_age = 0, // Immediate cleanup
    });
    defer analyzer.deinit();

    // Add patterns up to limit
    _ = try analyzer.analyzeMessage("First message");
    _ = try analyzer.analyzeMessage("Second message");
    _ = try analyzer.analyzeMessage("Third message"); // Should trigger cleanup

    try testing.expectEqual(@as(usize, 2), analyzer.getPatternCount());
}

test "pattern: metadata tracking" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    const msg = "Test message";
    const pattern = try analyzer.analyzeMessage(msg);
    try testing.expect(pattern != null);

    // Test metadata
    try testing.expectEqual(@as(u32, 1), pattern.?.metadata.frequency);
    try testing.expect(pattern.?.metadata.first_seen > 0);
    try testing.expect(pattern.?.metadata.last_seen > 0);
    try testing.expect(pattern.?.metadata.confidence > 0);
}

test "pattern: concurrent access" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    const ThreadContext = struct {
        analyzer: *nexlog.PatternAnalyzer,
        message: []const u8,

        fn run(ctx: @This()) !void {
            var i: usize = 0;
            while (i < 100) : (i += 1) {
                _ = try ctx.analyzer.analyzeMessage(ctx.message);
            }
        }
    };

    var threads: [3]std.Thread = undefined;
    const contexts = [_]ThreadContext{
        .{ .analyzer = &analyzer, .message = "Thread 1 message" },
        .{ .analyzer = &analyzer, .message = "Thread 2 message" },
        .{ .analyzer = &analyzer, .message = "Thread 3 message" },
    };

    // Start threads
    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, ThreadContext.run, .{contexts[i]});
    }

    // Wait for threads
    for (threads) |thread| {
        thread.join();
    }

    // Verify thread safety
    try testing.expect(analyzer.getPatternCount() > 0);
}

test "pattern: custom pattern types" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    const custom_msg = "CUSTOM_TYPE: Special message";
    const pattern = try analyzer.analyzeMessage(custom_msg);
    try testing.expect(pattern != null);
    try testing.expectEqual(nexlog.PatternType.custom, pattern.?.pattern_type);
}

// tests/pattern_tests.zig
test "auto categorization and variable rule test" {
    const allocator = testing.allocator;

    // Define some category rules for testing:
    // "security" requires at least two keywords from {"auth","breach","malware"}
    // "performance" requires at least one keyword from {"latency","slow","timeout"}
    const category_rules = &[_]nexlog.analysis.patterns.CategoryRule{
        .{
            .category = "security",
            .keywords = &[_][]const u8{ "auth", "breach", "malware" },
            .threshold = 2,
        },
        .{
            .category = "performance",
            .keywords = &[_][]const u8{ "latency", "slow", "timeout" },
            .threshold = 1,
        },
    };

    // Define variable rules:
    // If a token matches an IP regex, classify it as an ip_address variable.
    // If a token is purely numeric, classify it as a number variable.
    const var_rules = &[_]nexlog.analysis.patterns.VariableRule{
        .{ .name = "ip", .regex = "^\\d+\\.\\d+\\.\\d+\\.\\d+$", .var_type = .ip_address },
        .{ .name = "number", .regex = "^\\d+$", .var_type = .number },
    };

    var analyzer = nexlog.analysis.patterns.PatternAnalyzer.init(allocator, .{
        .similarity_threshold = 0.85,
        .max_pattern_age = 60 * 60 * 24,
        .max_patterns = 1000,
        .variable_rules = var_rules,
        .category_rules = category_rules,
    });
    defer analyzer.deinit();

    // Test a message that should fall into the "security" category:
    // Contains "auth" and "breach" (2 keywords required).
    // Also includes an IP that should be detected as a variable.
    const security_msg = "User auth breach detected from 192.168.1.100";
    const pattern = try analyzer.analyzeMessage(security_msg);
    try testing.expect(pattern != null);

    // Unwrap the optional pattern
    const p = pattern.?;
    try testing.expectEqualStrings("security", p.category);

    // Check that the IP was detected as a variable
    if (p.variables.items.len != 1) {
        std.debug.print("Variables Detected (Expected 1, Found {}):\n", .{p.variables.items.len});
        for (p.variables.items) |vara| {
            std.debug.print("  - Type: {any}, Value: {s}\n", .{ vara.var_type, vara.seen_values.items[0] });
        }
    }
    try testing.expectEqual(@as(usize, 1), p.variables.items.len);
    const vari = p.variables.items[0];
    try testing.expectEqual(types.VarType.ip_address, vari.var_type);
    try testing.expectEqualStrings("192.168.1.100", vari.seen_values.items[0]);

    // Test a message that should fall into the "performance" category:
    // Contains "latency" which is one of the keywords required.
    const perf_msg = "System latency is high";
    const pattern2 = try analyzer.analyzeMessage(perf_msg);
    try testing.expect(pattern2 != null);
    const p2 = pattern2.?; // Unwrap the optional
    try testing.expectEqualStrings("performance", p2.category);

    // Test a message that contains a numeric variable but doesn't meet any category threshold:
    const num_msg = "Request took 350ms";
    const pattern3 = try analyzer.analyzeMessage(num_msg);
    try testing.expect(pattern3 != null);
    const p3 = pattern3.?; // Unwrap the optional
    // No category keywords, so it should be "uncategorized"
    try testing.expectEqualStrings("uncategorized", p3.category);
    // Check the numeric variable detection
    try testing.expectEqual(@as(usize, 1), p3.variables.items.len);
    const var3 = p3.variables.items[0];
    try testing.expectEqual(types.VarType.number, var3.var_type);
    try testing.expectEqualStrings("350ms", var3.seen_values.items[0]);
}
