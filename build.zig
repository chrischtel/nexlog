const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nexlog_module = b.addModule("nexlog", .{
        .root_source_file = b.path("src/nexlog.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "nexlog",
        .root_module = nexlog_module,
        .linkage = .static,
    });

    b.installArtifact(lib);

    // Library unit tests
    const lib_unit_tests = b.addTest(.{ .root_module = nexlog_module });
    lib_unit_tests.root_module.addImport("nexlog", nexlog_module);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Test step that will run all tests
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Add tests from tests directory
    var tests_dir = std.fs.cwd().openDir("tests", .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        unreachable;
    };

    var it = tests_dir.iterate();
    while (it.next() catch unreachable) |entry| {
        if (entry.kind == .file) {
            const extension = std.fs.path.extension(entry.name);
            if (std.mem.eql(u8, extension, ".zig")) {
                const test_path = b.fmt("tests/{s}", .{entry.name});
                const test_exe = b.addTest(.{ .root_module = b.createModule(.{
                    .root_source_file = b.path(test_path),
                    .target = target,
                    .optimize = optimize,
                }) });
                test_exe.root_module.addImport("nexlog", nexlog_module);

                const run_test = b.addRunArtifact(test_exe);
                test_step.dependOn(&run_test.step);
            }
        }
    }

    // build.zig section for examples
    const examples = [_]struct {
        file: []const u8,
        name: []const u8,
        libc: bool = false,
    }{
        .{ .file = "examples/basic_usage.zig", .name = "example_1" },
        .{ .file = "examples/custom_handler.zig", .name = "example_2" },
        .{ .file = "examples/file_rotation.zig", .name = "example_3" },
        .{ .file = "examples/json_logging.zig", .name = "example_4" },
        .{ .file = "examples/logger_integration.zig", .name = "example_5" },
        .{ .file = "examples/structured_logging.zig", .name = "example_6" },
        .{ .file = "examples/benchmark.zig", .name = "bench" },
        .{ .file = "examples/metadata_ergonomics.zig", .name = "example_7" },
        .{ .file = "examples/formatting_test.zig", .name = "example_8" },
        .{ .file = "examples/context_tracking.zig", .name = "example_9" },
        .{ .file = "examples/async_demo.zig", .name = "example_async", .libc = true },
    };

    const all_examples_step = b.step("all-examples", "Run all examples (for CI)");

    {
        for (examples) |example| {
            const exe = b.addExecutable(.{
                .name = example.name,
                .root_module = b.createModule(.{
                    .target = target,
                    .optimize = optimize,
                    .root_source_file = b.path(example.file),
                }),
            });
            exe.root_module.addImport("nexlog", nexlog_module);
            if (example.libc) {
                exe.linkLibC();
            }
            b.installArtifact(exe);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_step = b.step(example.name, example.file);
            run_step.dependOn(&run_cmd.step);

            test_step.dependOn(&run_cmd.step);
            all_examples_step.dependOn(&run_cmd.step);
        }
    }
}
