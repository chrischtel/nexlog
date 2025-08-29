const std = @import("std");
const types = @import("types.zig");

/// Thread-local context storage for logging
pub const ContextManager = struct {
    // Use a mutex-protected HashMap to store per-thread context
    var context_map: std.HashMap(u64, types.LogContext, std.hash_map.AutoContext(u64), 80) = undefined;
    var context_mutex: std.Thread.Mutex = std.Thread.Mutex{};
    var initialized: bool = false;

    /// Initialize the context manager (call once at startup)
    pub fn init(allocator: std.mem.Allocator) void {
        context_mutex.lock();
        defer context_mutex.unlock();

        if (!initialized) {
            context_map = std.HashMap(u64, types.LogContext, std.hash_map.AutoContext(u64), 80).init(allocator);
            initialized = true;
        }
    }

    /// Deinitialize the context manager
    pub fn deinit() void {
        context_mutex.lock();
        defer context_mutex.unlock();

        if (initialized) {
            context_map.deinit();
            initialized = false;
        }
    }

    /// Set context for the current thread
    pub fn setContext(context: types.LogContext) void {
        const thread_id = std.Thread.getCurrentId();

        context_mutex.lock();
        defer context_mutex.unlock();

        if (initialized) {
            context_map.put(thread_id, context) catch {
                // If we can't store context, just continue without it
                return;
            };
        }
    }

    /// Get context for the current thread
    pub fn getContext() ?types.LogContext {
        const thread_id = std.Thread.getCurrentId();

        context_mutex.lock();
        defer context_mutex.unlock();

        if (initialized) {
            return context_map.get(thread_id);
        }
        return null;
    }

    /// Clear context for the current thread
    pub fn clearContext() void {
        const thread_id = std.Thread.getCurrentId();

        context_mutex.lock();
        defer context_mutex.unlock();

        if (initialized) {
            _ = context_map.remove(thread_id);
        }
    }

    /// Set request context (convenience method)
    pub fn setRequestContext(request_id: []const u8, operation: ?[]const u8) void {
        const context = if (operation) |op|
            types.LogContext.withOperation(request_id, op)
        else
            types.LogContext.withRequestId(request_id);
        setContext(context);
    }

    /// Add correlation ID to existing context
    pub fn addCorrelation(correlation_id: []const u8) void {
        if (getContext()) |current_context| {
            const new_context = current_context.withCorrelation(correlation_id);
            setContext(new_context);
        } else {
            // If no context exists, create one with just correlation
            const context = types.LogContext{
                .correlation_id = correlation_id,
            };
            setContext(context);
        }
    }

    /// Generate a simple request ID (basic implementation)
    pub fn generateRequestId(allocator: std.mem.Allocator) ![]u8 {
        const timestamp = std.time.timestamp();
        const thread_id = std.Thread.getCurrentId();
        return std.fmt.allocPrint(allocator, "req-{}-{}", .{ timestamp, thread_id });
    }

    /// Generate a simple correlation ID
    pub fn generateCorrelationId(allocator: std.mem.Allocator) ![]u8 {
        const timestamp = std.time.timestamp();
        const thread_id = std.Thread.getCurrentId();
        return std.fmt.allocPrint(allocator, "corr-{}-{}", .{ timestamp, thread_id });
    }
};
