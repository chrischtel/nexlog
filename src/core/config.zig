const LogLevel = @import("types.zig").LogLevel;

pub const LogConfig = struct {
    min_level: LogLevel = .info,
    enable_console: bool = true,
    enable_colors: bool = true,
    enable_file_logging: bool = false,
    file_path: ?[]const u8 = null,
    max_file_size: usize = 10 * 1024 * 1024, // 10MB
    enable_rotation: bool = true,
    max_rotated_files: usize = 5,
    buffer_size: usize = 4096,
    async_mode: bool = false,
    enable_metadata: bool = true,
};
