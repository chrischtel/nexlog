// examples/pattern_recognition.zig
const std = @import("std");
const nexlog = @import("nexlog");

fn simulateComplexLogs() ![]const []const u8 {
    return &[_][]const u8{
        "User session 123e4567-e89b-12d3-a456-426614174000 started from IP 192.168.1.100 with client_id=mobile_app",
        "User session 987fcdeb-51a2-12d3-a456-426614174000 started from IP 192.168.1.101 with client_id=web_client",
        "Session 123e4567-e89b-12d3-a456-426614174000 ended after 3600 seconds",
        "Error: Database connection failed after 5 retries - err_code=DB_001",
        "Critical Error: Master node 192.168.1.200 unreachable - cluster_health=degraded",
        "Warning: High latency detected (150ms) on endpoint /api/users",
        "Performance Metric: Query latency=50ms endpoint=/api/products method=GET",
        "System Metric: Memory usage=2.5GB, CPU=75%, Disk=80%",
        "Application Metric: Cache hit_rate=85.5% size=1.2GB",
        "Event: {\"type\": \"user_action\", \"action\": \"purchase\", \"amount\": 150.50, \"currency\": \"USD\"}",
        "Event: {\"type\": \"user_action\", \"action\": \"refund\", \"amount\": 75.25, \"currency\": \"USD\"}",
        "Error: Transaction 12345 failed - {\"error\": \"insufficient_funds\", \"account\": \"user_123\", \"required\": 100.00, \"available\": 75.50}",
        "Error: Authentication failed for user admin@example.com - {\"reason\": \"invalid_2fa\", \"attempts\": 3, \"next_try\": \"5min\"}",
    };
}

fn processLogBatch(analyzer: *nexlog.PatternAnalyzer, logs: []const []const u8) !void {
    for (logs) |msg| {
        _ = try analyzer.analyzeMessage(msg);
    }
}

fn handleBufferFull(analyzer: *nexlog.PatternAnalyzer) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Performing emergency cleanup...\n", .{});

    // Custom cleanup logic could go here
    _ = analyzer;
}

fn printErrorSet(comptime T: type) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("Error set: {}\n", .{@typeInfo(@typeInfo(T).Fn.return_type.?).ErrorUnion.error_set}) catch {};
}

/// Main function demonstrating advanced pattern analysis with auto-categorization and variable detection.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n=== Advanced Pattern Analysis Example ===\n\n", .{});

    // Define category rules for auto-categorization.
    const category_rules = &[_]nexlog.CategoryRule{
        .{
            .category = "security",
            .keywords = &[_][]const u8{
                "error",              "fail",        "authentication", "auth",
                "breach",             "malware",     "failed",         "transaction",
                "insufficient_funds", "invalid_2fa",
            },
            .threshold = 1, // Threshold adjusted as needed
        },
        .{
            .category = "performance",
            .keywords = &[_][]const u8{
                "latency", "slow",     "timeout", "performance",
                "metric",  "memory",   "cpu",     "disk",
                "cache",   "hit_rate",
            },
            .threshold = 1,
        },
        .{
            .category = "event",
            .keywords = &[_][]const u8{
                "event",   "user_action", "purchase", "refund",
                "session", "login",       "logout",
            },
            .threshold = 1,
        },
        .{
            .category = "metric",
            .keywords = &[_][]const u8{
                "memory", "cpu",     "disk", "cache", "hit_rate",
                "usage",  "latency",
            },
            .threshold = 1,
        },
        // Optional: Add more categories as needed
        .{
            .category = "warning",
            .keywords = &[_][]const u8{
                "warn", "warning", "degraded",
            },
            .threshold = 1,
        },
        .{
            .category = "debug",
            .keywords = &[_][]const u8{
                "debug",
            },
            .threshold = 1,
        },
        .{
            .category = "info",
            .keywords = &[_][]const u8{
                "info",
            },
            .threshold = 1,
        },
    };

    // Define variable rules for variable detection.
    // Note: Since regex support is not yet implemented, the `matchesRegex` function uses a stub.
    const var_rules = &[_]nexlog.VariableRule{
        .{ .name = "ip", .regex = "^\\d+\\.\\d+\\.\\d+\\.\\d+$", .var_type = .ip_address },
        .{ .name = "number", .regex = "^\\d+$", .var_type = .number },
        .{ .name = "uuid", .regex = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", .var_type = .uuid },
    };

    // Initialize the PatternAnalyzer with category and variable rules.
    var analyzer = nexlog.PatternAnalyzer.init(allocator, .{
        .similarity_threshold = 0.90,
        .max_patterns = 20,
        .max_pattern_age = 60 * 60, // 1 hour
        .variable_rules = var_rules,
        .category_rules = category_rules,
    });
    defer analyzer.deinit();

    // Simulate a batch of complex log messages.
    const logs = try simulateComplexLogs();

    // Process each log and print its pattern, category, and detected variables.
    for (logs) |msg| {
        const pattern_opt = try analyzer.analyzeMessage(msg);
        if (pattern_opt) |pattern| {
            const p = pattern;
            try stdout.print("\nLog: {s}\n", .{msg});
            try stdout.print("Pattern Type: {s}\n", .{@tagName(p.pattern_type)});
            try stdout.print("Category: {s}\n", .{p.category});

            // Print detected variables.
            if (p.variables.items.len > 0) {
                try stdout.print("Variables Detected:\n", .{});
                for (p.variables.items) |vari| {
                    try stdout.print("  - Type: {s}, Value: {s}\n", .{
                        @tagName(vari.var_type),
                        vari.seen_values.items[0],
                    });
                }
            } else {
                try stdout.print("No variables detected.\n", .{});
            }
        } else {
            try stdout.print("\nLog: {s}\nPattern: None (possibly categorized as 'uncategorized')\n", .{msg});
        }
    }

    try stdout.print("\n=== Pattern Analysis Results ===\n", .{});
    try stdout.print("Total Patterns Detected: {d}\n", .{analyzer.getPatternCount()});

    try stdout.print("\n=== Testing Error Conditions ===\n", .{});

    // Test with a very large message to trigger OutOfMemory error.
    {
        const large_message_size = 1000000; // 1,000,000 characters
        const large_message = try allocator.alloc(u8, large_message_size);
        defer allocator.free(large_message);
        for (large_message) |*c| {
            c.* = 'A';
        }

        const result = analyzer.analyzeMessage(large_message) catch |err| {
            try stdout.print("Expected error occurred while processing large message: {s}\n", .{@errorName(err)});
            return;
        };

        if (result == null) {
            try stdout.print("Large message was categorized as 'uncategorized'.\n", .{});
        }
    }

    // Test with an empty message.
    {
        const empty_msg = "";
        const result = analyzer.analyzeMessage(empty_msg) catch |err| {
            try stdout.print("Expected error occurred while processing empty message: {s}\n", .{@errorName(err)});
            return;
        };

        if (result == null) {
            try stdout.print("Empty message was categorized as 'uncategorized'.\n", .{});
        }
    }

    try stdout.print("\nExample completed successfully!\n", .{});
}
