const std = @import("std");
// core/types.zig
pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err, // Changed from 'error' to 'err'
    critical,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR", // Display string can still be "ERROR"
            .critical => "CRITICAL",
        };
    }

    pub fn toColor(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "\x1b[90m", // Gray
            .debug => "\x1b[36m", // Cyan
            .info => "\x1b[32m", // Green
            .warn => "\x1b[33m", // Yellow
            .err => "\x1b[31m", // Red
            .critical => "\x1b[35m", // Magenta
        };
    }
};

pub const Variable = struct {
    var_type: VarType,
    value: []const u8,
};

pub const LogContext = struct {
    // Request tracking
    request_id: ?[]const u8 = null, // Optional request ID for tracing
    correlation_id: ?[]const u8 = null, // Optional correlation ID for linking events
    trace_id: ?[]const u8 = null, // Optional trace ID for distributed tracing
    span_id: ?[]const u8 = null, // Optional span ID for distributed tracing

    // User/session tracking
    user_id: ?[]const u8 = null, // Optional user ID for user-specific logs
    session_id: ?[]const u8 = null, // Optional session ID for session-specific logs

    // Operation tracking
    operation: ?[]const u8 = null, // Optional operation name for context
    function: ?[]const u8 = null, // Optional function name for context

    // Call chain tracking
    call_depth: u32 = 0, // Depth of the call chain
    parent_function: ?[]const u8 = null, // Optional parent function name for context

    /// Create a basic context with just request ID
    pub fn withRequestId(request_id: []const u8) LogContext {
        return LogContext{
            .request_id = request_id,
        };
    }

    /// Create context with request ID and operation
    pub fn withOperation(request_id: []const u8, operation: []const u8) LogContext {
        return LogContext{
            .request_id = request_id,
            .operation = operation,
        };
    }

    /// Add correlation ID to existing context
    pub fn withCorrelation(self: LogContext, correlation_id: []const u8) LogContext {
        var new_context = self;
        new_context.correlation_id = correlation_id;
        return new_context;
    }
};

pub const LogMetadata = struct {
    timestamp: i64,
    thread_id: usize,
    file: []const u8,
    line: u32,
    function: []const u8,
    context: ?LogContext = null, // Optional context for additional metadata

    /// Create metadata with automatic source location capture
    pub fn create(src: std.builtin.SourceLocation) LogMetadata {
        return LogMetadata{
            .timestamp = std.time.timestamp(),
            .thread_id = getCurrentThreadId(),
            .file = src.file,
            .line = src.line,
            .function = src.fn_name,
        };
    }

    /// Create metadata with custom timestamp but automatic source location
    pub fn createWithTimestamp(timestamp: i64, src: std.builtin.SourceLocation) LogMetadata {
        return LogMetadata{
            .timestamp = timestamp,
            .thread_id = getCurrentThreadId(),
            .file = src.file,
            .line = src.line,
            .function = src.fn_name,
        };
    }

    /// Create metadata with custom thread ID but automatic source location
    pub fn createWithThreadId(thread_id: usize, src: std.builtin.SourceLocation) LogMetadata {
        return LogMetadata{
            .timestamp = std.time.timestamp(),
            .thread_id = thread_id,
            .file = src.file,
            .line = src.line,
            .function = src.fn_name,
        };
    }

    /// Create minimal metadata (just timestamp and thread)
    pub fn minimal() LogMetadata {
        return LogMetadata{
            .timestamp = std.time.timestamp(),
            .thread_id = getCurrentThreadId(),
            .file = "",
            .line = 0,
            .function = "",
        };
    }

    /// Create metadata with context from ContextManager
    pub fn createWithContext(src: std.builtin.SourceLocation, context: ?LogContext) LogMetadata {
        return LogMetadata{
            .timestamp = std.time.timestamp(),
            .thread_id = getCurrentThreadId(),
            .file = src.file,
            .line = src.line,
            .function = src.fn_name,
            .context = context,
        };
    }
};

/// Helper function to get current thread ID
fn getCurrentThreadId() usize {
    // Get the current thread ID as a u32 and convert to usize
    return @as(usize, std.Thread.getCurrentId());
}

/// Types of recognized patterns
pub const PatternType = enum {
    /// Regular log messages
    message,
    /// Error and exception patterns
    err,
    /// Metric and measurement patterns
    metric,
    /// System or application events
    event,
    /// Custom pattern type
    custom,

    pub fn toString(self: PatternType) []const u8 {
        return switch (self) {
            .message => "MESSAGE",
            .err => "ERROR",
            .metric => "METRIC",
            .event => "EVENT",
            .custom => "CUSTOM",
        };
    }
};

/// Variable elements in a pattern
pub const PatternVariable = struct {
    /// Position in the pattern
    position: usize,
    /// Type of the variable
    var_type: VarType,
    /// Previously seen values
    seen_values: std.ArrayList([]const u8),
};

/// Types of variables that can be detected
pub const VarType = enum {
    string,
    number,
    date,
    uuid,
    email,
    ip_address,
    path,
    url,
    custom,

    pub fn fromValue(value: []const u8) VarType {
        // Basic type detection
        if (std.ascii.isDigit(value[0])) return .number;
        if (isUuid(value)) return .uuid;
        if (isEmail(value)) return .email;
        if (isIpAddress(value)) return .ip_address;
        if (isUrl(value)) return .url;
        if (isPath(value)) return .path;
        return .string;
    }
};

/// Pattern metadata for tracking and analysis
pub const PatternMetadata = struct {
    /// When the pattern was first seen
    first_seen: i64,
    /// When the pattern was last seen
    last_seen: i64,
    /// Number of occurrences
    frequency: u32,
    /// Pattern match confidence (0.0 - 1.0)
    confidence: f32,
    /// Tags for categorization
    tags: []const []const u8 = &[_][]const u8{},
    /// Source of the pattern (file, function, etc)
    source: ?[]const u8 = null,
};

/// Pattern match result
pub const PatternMatch = struct {
    /// The matched pattern template
    pattern: []const u8,
    /// Pattern type
    pattern_type: PatternType,
    /// Variables found in the match
    variables: []PatternVariable,
    /// Match confidence score (0.0 - 1.0)
    confidence: f32,
    /// Original message that matched
    original_message: []const u8,
};

/// Configuration for pattern analysis
pub const PatternConfig = struct {
    /// Minimum similarity threshold (0.0 - 1.0)
    similarity_threshold: f32 = 0.85,
    /// Maximum age of patterns before cleanup (seconds)
    max_pattern_age: i64 = 60 * 60 * 24, // 24 hours
    /// Maximum number of patterns to store
    max_patterns: usize = 1000,
    /// Enable variable detection
    enable_variable_detection: bool = true,
    /// Minimum variable frequency to consider
    min_variable_frequency: u32 = 3,
};

// Helper functions for type detection
fn isUuid(value: []const u8) bool {
    if (value.len != 36) return false;
    // Basic UUID format check (8-4-4-4-12)
    return std.mem.eql(u8, "-", value[8..9]) and
        std.mem.eql(u8, "-", value[13..14]) and
        std.mem.eql(u8, "-", value[18..19]) and
        std.mem.eql(u8, "-", value[23..24]);
}

fn isEmail(value: []const u8) bool {
    return std.mem.indexOf(u8, value, "@") != null;
}

fn isIpAddress(value: []const u8) bool {
    // Very basic IPv4 check
    var dots: u8 = 0;
    for (value) |char| {
        if (char == '.') dots += 1;
    }
    return dots == 3;
}

fn isUrl(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "http://") or
        std.mem.startsWith(u8, value, "https://");
}

fn isPath(value: []const u8) bool {
    return std.mem.indexOf(u8, value, "/") != null or
        std.mem.indexOf(u8, value, "\\") != null;
}
