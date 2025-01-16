const std = @import("std");
const logger = @import("logger.zig");
const config = @import("config.zig");
const errors = @import("errors.zig");
const types = @import("types.zig");

/// Global logger state
pub const GlobalState = struct {
    is_initialized: bool = false,
    default_logger: ?*logger.Logger = null,
    allocator: ?std.mem.Allocator = null,
    mutex: std.Thread.Mutex = .{},

    const Self = @This();

    pub fn init(self: *Self, alloc: std.mem.Allocator, cfg: config.LogConfig) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_initialized) {
            return errors.LogError.AlreadyInitialized;
        }

        self.allocator = alloc;
        self.default_logger = try logger.Logger.init(alloc, cfg);
        self.is_initialized = true;
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.default_logger) |log| {
            log.deinit();
            self.default_logger = null;
        }
        self.allocator = null;
        self.is_initialized = false;
    }
};

/// Global state instance
var global_state = GlobalState{};

/// Initialize the logging system with default configuration
pub fn init(allocator: std.mem.Allocator) !void {
    const default_config = config.LogConfig{
        .min_level = .info,
        .enable_colors = true,
        .enable_file_logging = false,
        .file_path = null,
        .buffer_size = 4096,
        .async_mode = false,
        .enable_metadata = true,
        .max_file_size = 10 * 1024 * 1024,
        .enable_rotation = true,
        .max_rotated_files = 5,
    };
    return initWithConfig(allocator, default_config);
}

/// Initialize with custom configuration
pub fn initWithConfig(allocator: std.mem.Allocator, cfg: config.LogConfig) !void {
    return global_state.init(allocator, cfg);
}

/// Deinitialize the logging system
pub fn deinit() void {
    global_state.deinit();
}

/// Get the default logger instance
pub fn getDefaultLogger() ?*logger.Logger {
    return global_state.default_logger;
}

/// Check if logging system is initialized
pub fn isInitialized() bool {
    return global_state.is_initialized;
}

/// Builder pattern for configuration
pub const LogBuilder = struct {
    config: config.LogConfig,

    pub fn init() LogBuilder {
        return .{
            .config = .{
                .min_level = .info,
                .enable_colors = true,
                .enable_file_logging = false,
                .file_path = null,
                .buffer_size = 4096,
                .async_mode = false,
                .enable_metadata = true,
                .max_file_size = 10 * 1024 * 1024,
                .enable_rotation = true,
                .max_rotated_files = 5,
            },
        };
    }

    pub fn setMinLevel(self: *LogBuilder, level: types.LogLevel) *LogBuilder {
        self.config.min_level = level;
        return self;
    }

    pub fn enableColors(self: *LogBuilder, enable: bool) *LogBuilder {
        self.config.enable_colors = enable;
        return self;
    }

    pub fn setBufferSize(self: *LogBuilder, size: usize) *LogBuilder {
        self.config.buffer_size = size;
        return self;
    }

    pub fn enableFileLogging(self: *LogBuilder, enable: bool, path: ?[]const u8) *LogBuilder {
        self.config.enable_file_logging = enable;
        self.config.file_path = path;
        return self;
    }

    pub fn setMaxFileSize(self: *LogBuilder, size: usize) *LogBuilder {
        self.config.max_file_size = size;
        return self;
    }

    pub fn setMaxRotatedFiles(self: *LogBuilder, count: usize) *LogBuilder {
        self.config.max_rotated_files = count;
        return self;
    }

    pub fn enableRotation(self: *LogBuilder, enable: bool) *LogBuilder {
        self.config.enable_rotation = enable;
        return self;
    }

    pub fn enableAsyncMode(self: *LogBuilder, enable: bool) *LogBuilder {
        self.config.async_mode = enable;
        return self;
    }

    pub fn enableMetadata(self: *LogBuilder, enable: bool) *LogBuilder {
        self.config.enable_metadata = enable;
        return self;
    }

    pub fn build(self: *LogBuilder, allocator: std.mem.Allocator) !void {
        return initWithConfig(allocator, self.config);
    }
};
