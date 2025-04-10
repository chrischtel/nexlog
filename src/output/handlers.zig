const std = @import("std");
const types = @import("../core/types.zig");

/// Handler types for identification
pub const HandlerType = enum {
    console,
    file,
    network,
    custom,
};

/// Interface that all log handlers must implement
pub const LogHandler = struct {
    /// Type of the handler
    handler_type: HandlerType,

    /// Pointer to implementation of writeLog
    writeLogFn: *const fn (
        ctx: *anyopaque,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) anyerror!void,

    writeFormattedLogFn: *const fn (
        ctx: *anyopaque,
        formatted_message: []const u8,
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
        handler_type: HandlerType,
        comptime writeLogFnT: fn (
            ptr: @TypeOf(pointer),
            level: types.LogLevel,
            message: []const u8,
            metadata: ?types.LogMetadata,
        ) anyerror!void,
        comptime writeFormattedLogFnT: fn (
            ptr: @TypeOf(pointer),
            formatted_message: []const u8,
        ) anyerror!void,
        comptime flushFnT: fn (ptr: @TypeOf(pointer)) anyerror!void,
        comptime deinitFnT: fn (ptr: @TypeOf(pointer)) void,
    ) LogHandler {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);
        if (@hasField(std.builtin.Type, "pointer")) {
            std.debug.assert(ptr_info == .pointer); // Must be a pointer
            std.debug.assert(ptr_info.pointer.size == .one); // Must be a single-item pointer
        } else {
            std.debug.assert(ptr_info == .Pointer); // Must be a pointer
            std.debug.assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer        }
        }

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

        const GenericWriteFormattedLog = struct {
            fn implementation(
                ctx: *anyopaque,
                formatted_message: []const u8,
            ) !void {
                const self = @as(Ptr, @alignCast(@ptrCast(ctx)));
                return writeFormattedLogFnT(self, formatted_message);
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
            .handler_type = handler_type,
            .writeLogFn = GenericWriteLog,
            .writeFormattedLogFn = GenericWriteFormattedLog,
            .flushFn = GenericFlush,
            .deinitFn = GenericDeinit,
            .ctx = pointer,
        };
    }

    pub fn writeLog(
        self: LogHandler,
        level: types.LogLevel,
        message: []const u8,
        metadata: ?types.LogMetadata,
    ) !void {
        return self.writeLogFn(self.ctx, level, message, metadata);
    }

    pub fn writeFormattedLog(self: LogHandler, formatted_message: []const u8) !void {
        return self.writeFormattedLogFn(self.ctx, formatted_message);
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
