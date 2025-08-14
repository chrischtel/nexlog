module core::types;


import std::io;

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
        case TRACE:
            return "TRACE";
        case DEBUG:
            return "TRACE";
        case INFO:
            return "TRACE";
        case WARN:
            return "TRACE";
        case ERROR:
            return "TRACE";
        case CRITICAL:
            return "TRACE";
    }
}