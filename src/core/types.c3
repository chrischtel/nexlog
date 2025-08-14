module core::types;

enum LogLevel : int {
    TRACE,
    DEBUG,
    INFO,
    WARN,
    ERROR,
    CRITICAL,
}

fn String LogLevel.to_string(self) {
    switch (self) {
        case TRACE:         return "TRACE";
        case DEBUG:         return "DEBUG";
        case INFO:          return "INFO";
        case WARN:          return "WARN";
        case ERROR:         return "ERROR";
        case CRITICAL:      return "CRITICAL";
    }
}

fn String LogLevel.to_color(self) {
    switch (self) {
        case TRACE:         return "\x1b[90m";
        case DEBUG:         return "\x1b[36m";
        case INFO:          return "\x1b[32m";
        case WARN:          return "\x1b[33m";
        case ERROR:         return "\x1b[31m";
        case CRITICAL:      return "\x1b[35m";
    }
}