const std = @import("std");
const nexlog = @import("nexlog");
const logger = nexlog.core.logger;
const types = nexlog.core.types;
const format = nexlog.utils.format;
const init = @import("nexlog").init;

const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_time_ns: u64,
    avg_time_ns: u64,
    throughput: f64, // logs per second
};

const BenchmarkError = error{
    OutOfMemory,
    InvalidPlaceholder,
    InvalidFormat,
    MissingHandler,
    TimestampError,
    TimerUnsupported,
    LoggerNotInitialized,
    NoSpaceLeft,
    InvalidUtf8,
    MetadataError,
    FileTooBig,
    DeviceBusy,
    AccessDenied,
    SystemResources,
    WouldBlock,
    NoDevice,
    Unexpected,
    SharingViolation,
    PathAlreadyExists,
    FileNotFound,
    PipeBusy,
    NameTooLong,
    InvalidWtf8,
    BadPathName,
    NetworkNotFound,
    AntivirusInterference,
    SymLinkLoop,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    IsDir,
    NotDir,
    FileLocksNotSupported,
    FileBusy,
    Unseekable,
    BufferFull,
    InvalidLogLevel,
    MessageTooLarge,
    FileLockFailed,
    FileRotationFailed,
    InvalidConfiguration,
    ThreadInitFailed,
    FormattingError,
    FilterError,
    AlreadyInitialized,
    NotInitialized,
    InvalidPath,
    InvalidBufferSize,
    InvalidMaxSize,
    InvalidRotationPolicy,
    InvalidFilterExpression,
    InvalidTimeFormat,
    ConflictingOptions,
    BufferOverflow,
    BufferUnderflow,
    InvalidAlignment,
    FlushFailed,
    CompactionFailed,
    PermissionDenied,
    DirectoryNotFound,
    DiskFull,
    RotationLimitReached,
    InvalidFilePath,
    LockTimeout,
};

fn runBenchmark(
    allocator: std.mem.Allocator,
    name: []const u8,
    iterations: usize,
    comptime benchmarkFn: fn (allocator: std.mem.Allocator) anyerror!void,
) anyerror!BenchmarkResult {
    var timer = try std.time.Timer.start();
    var total_time_ns: u64 = 0;

    // Warm up
    try benchmarkFn(allocator);

    // Run the benchmark
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const start_time = timer.read();
        try benchmarkFn(allocator);
        const end_time = timer.read();
        total_time_ns += end_time - start_time;
    }

    const avg_time_ns = total_time_ns / iterations;
    const throughput = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_time_ns)) / 1_000_000_000.0);

    return BenchmarkResult{
        .name = name,
        .iterations = iterations,
        .total_time_ns = total_time_ns,
        .avg_time_ns = avg_time_ns,
        .throughput = throughput,
    };
}

fn printBenchmarkResults(results: []const BenchmarkResult) void {
    std.debug.print("\n=== Benchmark Results ===\n", .{});
    std.debug.print("{s:<20} {s:<10} {s:<15} {s:<15}\n", .{ "Benchmark", "Iterations", "Avg Time (ns)", "Throughput (logs/s)" });
    std.debug.print("{s:-<20} {s:-<10} {s:-<15} {s:-<15}\n", .{ "", "", "", "" });

    for (results) |result| {
        std.debug.print("{s:<20} {d:<10} {d:<15} {d:.2}\n", .{
            result.name,
            result.iterations,
            result.avg_time_ns,
            result.throughput,
        });
    }
    std.debug.print("\n", .{});
}

fn benchmarkJsonFormat(allocator: std.mem.Allocator) !void {
    const config = format.FormatConfig{
        .structured_format = .json,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };
    const formatter = try format.Formatter.init(allocator, config);
    defer formatter.deinit();

    const fields = [_]format.StructuredField{
        .{
            .name = "user_id",
            .value = "12345",
        },
        .{
            .name = "action",
            .value = "login",
        },
        .{
            .name = "ip",
            .value = "192.168.1.1",
        },
    };

    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "benchmark.zig",
        .line = 42,
        .function = "benchmarkJsonFormat",
    };

    const formatted = try formatter.formatStructured(
        .info,
        "User logged in successfully",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);
}

fn benchmarkLogfmtFormat(allocator: std.mem.Allocator) !void {
    const config = format.FormatConfig{
        .structured_format = .logfmt,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };
    const formatter = try format.Formatter.init(allocator, config);
    defer formatter.deinit();

    const fields = [_]format.StructuredField{
        .{
            .name = "user_id",
            .value = "12345",
        },
        .{
            .name = "action",
            .value = "login",
        },
        .{
            .name = "ip",
            .value = "192.168.1.1",
        },
    };

    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "benchmark.zig",
        .line = 42,
        .function = "benchmarkLogfmtFormat",
    };

    const formatted = try formatter.formatStructured(
        .info,
        "User logged in successfully",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);
}

fn benchmarkCustomFormat(allocator: std.mem.Allocator) !void {
    const config = format.FormatConfig{
        .structured_format = .custom,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
        .custom_field_separator = " | ",
        .custom_key_value_separator = "=",
    };
    const formatter = try format.Formatter.init(allocator, config);
    defer formatter.deinit();

    const fields = [_]format.StructuredField{
        .{
            .name = "user_id",
            .value = "12345",
        },
        .{
            .name = "action",
            .value = "login",
        },
        .{
            .name = "ip",
            .value = "192.168.1.1",
        },
    };

    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "benchmark.zig",
        .line = 42,
        .function = "benchmarkCustomFormat",
    };

    const formatted = try formatter.formatStructured(
        .info,
        "User logged in successfully",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);
}

fn benchmarkLargeFields(allocator: std.mem.Allocator) !void {
    const config = format.FormatConfig{
        .structured_format = .json,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };
    const formatter = try format.Formatter.init(allocator, config);
    defer formatter.deinit();

    // Create a large JSON object as a string
    var large_json = std.ArrayList(u8){};
    defer large_json.deinit(allocator);

    try large_json.appendSlice(allocator, "{\"data\":[");
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        if (i > 0) try large_json.appendSlice(allocator, ",");
        try large_json.appendSlice(allocator, "{\"id\":");
        try std.fmt.format(large_json.writer(allocator), "{d}", .{i});
        try large_json.appendSlice(allocator, ",\"value\":\"some data\"}");
    }
    try large_json.appendSlice(allocator, "]}");

    const fields = [_]format.StructuredField{
        .{
            .name = "user_id",
            .value = "12345",
        },
        .{
            .name = "action",
            .value = "login",
        },
        .{
            .name = "data",
            .value = large_json.items,
        },
    };

    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "benchmark.zig",
        .line = 42,
        .function = "benchmarkLargeFields",
    };

    const formatted = try formatter.formatStructured(
        .info,
        "User logged in with large data payload",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);
}

fn benchmarkManyFields(allocator: std.mem.Allocator) !void {
    const config = format.FormatConfig{
        .structured_format = .json,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };
    const formatter = try format.Formatter.init(allocator, config);
    defer formatter.deinit();

    // Create many fields
    var fields = std.ArrayList(format.StructuredField){};
    defer fields.deinit(allocator);

    var i: usize = 0;
    while (i < 50) : (i += 1) {
        var name_buf: [20]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "field_{d}", .{i}) catch continue;

        var value_buf: [20]u8 = undefined;
        const value = std.fmt.bufPrint(&value_buf, "value_{d}", .{i}) catch continue;

        try fields.append(allocator, .{
            .name = name,
            .value = value,
        });
    }

    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "benchmark.zig",
        .line = 42,
        .function = "benchmarkManyFields",
    };

    const formatted = try formatter.formatStructured(
        .info,
        "Log with many fields",
        fields.items,
        metadata,
    );
    defer allocator.free(formatted);
}

fn benchmarkWithAttributes(allocator: std.mem.Allocator) !void {
    const config = format.FormatConfig{
        .structured_format = .json,
        .include_timestamp_in_structured = true,
        .include_level_in_structured = true,
    };
    const formatter = try format.Formatter.init(allocator, config);
    defer formatter.deinit();

    // Create fields with attributes
    var user_attrs = std.StringHashMap(u8).init(allocator);
    defer user_attrs.deinit();
    try user_attrs.put("role", 'A'); // 'A' for admin
    try user_attrs.put("permissions", '*'); // '*' for all

    var action_attrs = std.StringHashMap(u8).init(allocator);
    defer action_attrs.deinit();
    try action_attrs.put("type", 'W'); // 'W' for web
    try action_attrs.put("method", 'P'); // 'P' for POST

    const fields = [_]format.StructuredField{
        .{
            .name = "user_id",
            .value = "12345",
            .attributes = user_attrs,
        },
        .{
            .name = "action",
            .value = "login",
            .attributes = action_attrs,
        },
        .{
            .name = "ip",
            .value = "192.168.1.1",
        },
    };

    const metadata = types.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 1234,
        .file = "benchmark.zig",
        .line = 42,
        .function = "benchmarkWithAttributes",
    };

    const formatted = try formatter.formatStructured(
        .info,
        "User logged in with attributes",
        &fields,
        metadata,
    );
    defer allocator.free(formatted);
}

fn benchmarkLoggerIntegration(allocator: std.mem.Allocator) !void {
    // Initialize the logging system
    try nexlog.init(allocator);
    defer nexlog.deinit();

    // Get the default logger
    const log = nexlog.getDefaultLogger() orelse return error.LoggerNotInitialized;

    // Log a message
    try log.log(.info, "User logged in successfully", .{}, null);
}

fn benchmarkLoggerIntegrationWrapper(allocator: std.mem.Allocator) BenchmarkError!void {
    benchmarkLoggerIntegration(allocator) catch |err| {
        return switch (err) {
            error.IOError => BenchmarkError.FileTooBig,
            error.ConfigError => BenchmarkError.InvalidConfiguration,
            error.BufferError => BenchmarkError.BufferFull,
            error.Unexpected => BenchmarkError.Unexpected,
            else => BenchmarkError.Unexpected,
        };
    };
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const iterations = 10_000;
    var results: std.ArrayList(BenchmarkResult) = .empty;
    defer results.deinit(allocator);

    // Run benchmarks
    try results.append(allocator, try runBenchmark(allocator, "JSON Format", iterations, benchmarkJsonFormat));
    try results.append(allocator, try runBenchmark(allocator, "Logfmt Format", iterations, benchmarkLogfmtFormat));
    try results.append(allocator, try runBenchmark(allocator, "Custom Format", iterations, benchmarkCustomFormat));
    try results.append(allocator, try runBenchmark(allocator, "Large Fields", iterations / 10, benchmarkLargeFields));
    try results.append(allocator, try runBenchmark(allocator, "Many Fields", iterations / 2, benchmarkManyFields));
    try results.append(allocator, try runBenchmark(allocator, "With Attributes", iterations, benchmarkWithAttributes));
    try results.append(allocator, try runBenchmark(allocator, "Logger Integration", iterations, benchmarkLoggerIntegrationWrapper));

    // Print results
    printBenchmarkResults(results.items);
}
