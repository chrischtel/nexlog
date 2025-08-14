module core::config;
import core::types;

struct LogConfig {
    LogLevel min_level;
    bool     enable_console;
    bool     enable_colors;
    bool     enable_file_logging;
    ZString  file_path;
    usz      max_file_size;
    bool     enable_rotation;
    usz      max_rotated_files;
    usz      buffer_size;
    bool     async_mode;
    bool     enable_metadata;
    // TODO
    //format::FormatConfig? format_config;
}