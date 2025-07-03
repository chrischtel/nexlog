# Async Support Design for nexlog

## Current Limitations for Async Runtimes (like Zuki)

### What nexlog has:
- Thread-safe logging with mutexes
- Thread ID tracking
- Basic `async_mode` config flag (not implemented)

### What's missing for full async support:
- Non-blocking logging operations
- Async I/O for file writes
- Background log processing
- Async handler interface
- Backpressure handling

## Proposed Async Design

### 1. Async Logger Interface
```zig
pub const AsyncLogger = struct {
    pub fn logAsync(self: *Self, level: LogLevel, message: []const u8, metadata: ?LogMetadata) !void {
        // Queue log entry for background processing
        try self.log_queue.push(LogEntry{ .level = level, .message = message, .metadata = metadata });
    }
    
    pub fn flushAsync(self: *Self) !void {
        // Async flush of all queued entries
    }
};
```

### 2. Async Handlers
```zig
pub const AsyncHandler = struct {
    pub fn logAsync(self: *Self, entry: LogEntry) !void {
        // Non-blocking log processing
    }
    
    pub fn flushAsync(self: *Self) !void {
        // Async flush implementation
    }
};
```

### 3. Background Processing
```zig
pub const LogProcessor = struct {
    queue: AsyncQueue(LogEntry),
    handlers: []AsyncHandler,
    
    pub fn processLoop(self: *Self) !void {
        while (true) {
            const entry = try self.queue.pop();
            for (self.handlers) |handler| {
                try handler.logAsync(entry);
            }
        }
    }
};
```

### 4. Integration Points for Zuki

For nexlog to work well with Zuki async runtime:

1. **Replace blocking I/O**: Use Zuki's async file operations
2. **Async-aware queues**: Use Zuki's async channels/queues  
3. **Task spawning**: Use Zuki's task spawner for background processing
4. **Async timers**: For flush intervals and rotation schedules

### 5. Migration Strategy

**Phase 1: Async Interface Layer**
- Add async methods alongside sync ones
- Implement async queuing internally
- Maintain backward compatibility

**Phase 2: Async Handlers**  
- AsyncFileHandler using Zuki's async I/O
- AsyncNetworkHandler for remote logging
- AsyncConsoleHandler for non-blocking output

**Phase 3: Full Async Runtime**
- Replace all blocking operations
- Integrate with Zuki's scheduler
- Optimize for async performance

## Quick Solution for Zuki

For immediate use with Zuki, you could:

1. **Wrap in async**: Call existing nexlog from Zuki tasks
2. **Background thread**: Run nexlog in dedicated thread, send via channels
3. **Queue approach**: Buffer logs in async-safe queue, process in background

```zig
// Quick wrapper for Zuki
pub const ZukiLogger = struct {
    nexlog_logger: *nexlog.Logger,
    log_channel: zuki.Channel(LogEntry),
    
    pub fn init(allocator: std.mem.Allocator) !*Self {
        const logger = try nexlog.Logger.init(allocator, .{});
        const channel = try zuki.Channel(LogEntry).init();
        
        // Spawn background task to process logs
        try zuki.spawn(processLogs, .{ logger, channel });
        
        return .{ .nexlog_logger = logger, .log_channel = channel };
    }
    
    pub fn logAsync(self: *Self, level: LogLevel, message: []const u8) !void {
        try self.log_channel.send(LogEntry{ .level = level, .message = message });
    }
    
    fn processLogs(logger: *nexlog.Logger, channel: zuki.Channel(LogEntry)) !void {
        while (true) {
            const entry = try channel.recv();
            try logger.log(entry.level, entry.message, .{}, null);
        }
    }
};
```
