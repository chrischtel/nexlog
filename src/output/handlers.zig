const std = @import("std");
const types = @import("../core/types.zig");

/// Interface that all log handlers must implement
pub const LogHandler = struct {
    /// Pointer to implementation of writeLog
    writeLogFn: *const fn (
        ctx: *anyopaque,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) anyerror!void,

    /// Pointer to implementation of flush
    flushFn: *const fn (ctx: *anyopaque) anyerror!void,

    /// Pointer to implementation of deinit
    deinitFn: *const fn (ctx: *anyopaque) void,

    /// Context pointer to the actual handler instance
    ctx: *anyopaque,

    /// Create a LogHandler interface from a specific handler type
    pub fn init(
        pointer: anytype,
        comptime writeLogFnT: fn (
            ptr: @TypeOf(pointer),
            level: types.LogLevel,
            message: []const u8,
            metadata: ?types.LogMetadata,
        ) anyerror!void,
        comptime flushFnT: fn (ptr: @TypeOf(pointer)) anyerror!void,
        comptime deinitFnT: fn (ptr: @TypeOf(pointer)) void,
    ) LogHandler {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        std.debug.assert(ptr_info == .Pointer); // Must be a pointer
        std.debug.assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer

        const GenericWriteLog = struct {
            fn implementation(
                ctx: *anyopaque,
                level: types.LogLevel,
                message: []const u8,
                metadata: ?types.LogMetadata,
            ) !void {
                const self = @as(Ptr, @alignCast(@ptrCast(ctx)));
                return writeLogFnT(self, level, message, metadata);
            }
        }.implementation;

        const GenericFlush = struct {
            fn implementation(ctx: *anyopaque) !void {
                const self = @as(Ptr, @alignCast(@ptrCast(ctx)));
                return flushFnT(self);
            }
        }.implementation;

        const GenericDeinit = struct {
            fn implementation(ctx: *anyopaque) void {
                const self = @as(Ptr, @alignCast(@ptrCast(ctx)));
                deinitFnT(self);
            }
        }.implementation;

        return .{
            .writeLogFn = GenericWriteLog,
            .flushFn = GenericFlush,
            .deinitFn = GenericDeinit,
            .ctx = pointer,
        };
    }

    /// Write a log message using this handler
    pub fn writeLog(
        self: LogHandler,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) !void {
        return self.writeLogFn(self.ctx, level, message, metadata);
    }

    /// Flush any buffered output
    pub fn flush(self: LogHandler) !void {
        return self.flushFn(self.ctx);
    }

    /// Clean up the handler
    pub fn deinit(self: LogHandler) void {
        self.deinitFn(self.ctx);
    }
};
