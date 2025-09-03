const std = @import("std");
const types = @import("../core/types.zig");
const handlers = @import("handlers.zig");
const json = @import("../utils/json.zig");
const errors = @import("../core/errors.zig");

pub const JsonHandlerConfig = struct {
    min_level: types.LogLevel = .debug,
    pretty_print: bool = false,
    buffer_size: usize = 4096,
    output_file: ?[]const u8 = null,
};

pub const JsonHandler = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    config: JsonHandlerConfig,
    file: ?std.fs.File,
    has_written: bool,
    is_initialized: bool,

    pub fn init(allocator: std.mem.Allocator, config: JsonHandlerConfig) errors.Error!*Self {
        // Allocate the handler first
        var handler = allocator.create(Self) catch {
            return errors.Error.BufferError;
        };
        errdefer allocator.destroy(handler);

        // Initialize with safe defaults
        handler.* = .{
            .allocator = allocator,
            .config = config,
            .file = null,
            .has_written = false,
            .is_initialized = false,
        };

        // Handle file creation separately
        if (config.output_file) |path| {
            handler.file = std.fs.createFileAbsolute(path, .{
                .read = true,
                .truncate = true,
            }) catch {
                allocator.destroy(handler);
                return errors.Error.IOError;
            };

            // Write initial bracket
            handler.file.?.writeAll("[\n") catch {
                handler.file.?.close();
                allocator.destroy(handler);
                return errors.Error.IOError;
            };
        }

        handler.is_initialized = true;
        return handler;
    }

    pub fn deinit(self: *Self) void {
        // Guard against double-free
        if (!self.is_initialized) return;

        // Create local copies of needed values
        const was_written = self.has_written;
        const allocator = self.allocator;

        // Mark as not initialized first
        self.is_initialized = false;

        // Handle file cleanup
        if (self.file) |file| {
            // Write closing content
            if (was_written) {
                file.writeAll("\n]") catch {};
            } else {
                file.writeAll("[]") catch {};
            }

            // Close the file
            file.close();
        }

        // Clear all fields before destruction
        self.* = undefined;

        // Finally destroy the handler
        allocator.destroy(self);
    }

    pub fn log(
        self: *Self,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) errors.Error!void {
        if (!self.is_initialized) return errors.Error.ConfigError;

        // Early return for filtered levels
        if (@intFromEnum(level) < @intFromEnum(self.config.min_level)) {
            return;
        }

        const json_str = json.serializeLogEntry(
            self.allocator,
            level,
            message,
            metadata,
        ) catch {
            return errors.Error.BufferError;
        };
        defer self.allocator.free(json_str);

        if (self.file) |*file| {
            // Add comma if not first entry
            if (self.has_written) {
                file.writeAll(",\n") catch {
                    return errors.Error.IOError;
                };
            }
            file.writeAll(json_str) catch {
                return errors.Error.IOError;
            };
            self.has_written = true;
        } else {
            var stdout_buffer: [1024]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            stdout.print("{s}\n", .{json_str}) catch {
                return errors.Error.IOError;
            };
            stdout.flush() catch {
                return errors.Error.IOError;
            };
        }
    }

    pub fn writeFormattedLog(
        self: *Self,
        formatted_message: []const u8,
    ) errors.Error!void {
        if (!self.is_initialized) return errors.Error.ConfigError;

        // For the JSON handler, we handle formatted messages by writing them directly
        // But we need to ensure the JSON structure is maintained

        if (self.file) |*file| {
            // Add comma if not first entry
            if (self.has_written) {
                file.writeAll(",\n") catch {
                    return errors.Error.IOError;
                };
            }

            // Since we don't know the structure of the formatted message,
            // we'll wrap it in a simplified JSON object
            const buf = self.allocator.alloc(u8, formatted_message.len + 40) catch {
                return errors.Error.BufferError;
            };
            defer self.allocator.free(buf);

            const json_wrapper = std.fmt.bufPrint(
                buf,
                "{{ \"message\": \"{s}\" }}",
                .{formatted_message},
            ) catch {
                // Fallback to direct writing if formatting fails
                file.writeAll(formatted_message) catch {
                    return errors.Error.IOError;
                };
                self.has_written = true;
                return errors.Error.BufferError;
            };

            file.writeAll(json_wrapper) catch {
                return errors.Error.IOError;
            };
            self.has_written = true;
        } else {
            var stdout_buffer: [1024]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            stdout.print("{s}\n", .{formatted_message}) catch {
                return errors.Error.IOError;
            };
            stdout.flush() catch {
                return errors.Error.IOError;
            };
        }
    }

    pub fn flush(self: *Self) errors.Error!void {
        if (!self.is_initialized) return errors.Error.ConfigError;
        if (self.file) |*file| {
            file.sync() catch {
                return errors.Error.IOError;
            };
        }
    }

    pub fn toLogHandler(self: *Self) handlers.LogHandler {
        return handlers.LogHandler.init(
            self,
            .custom,
            JsonHandler.log,
            JsonHandler.writeFormattedLog,
            JsonHandler.flush,
            JsonHandler.deinit,
        );
    }
};
