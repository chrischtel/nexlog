module core::types;
import std::ascii;

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

struct Variable {
    VarType var_type;
    String value;
}

enum VarType {
    STRING,
    NUMBER,
    DATE,
    UUID,
    EMAIL,
    IP_ADRESS,
    PATH,
    URL,
    CUSTOM,
}


fn VarType VarType.fromValue(self, String value) {
    if (ascii::is_digit_m(value[0])) return NUMBER;
    if (is_uuid(value)) return UUID;
    if (is_email(value)) return EMAIL;
    if (is_ip_address(value)) return IP_ADRESS;
    if (is_url(value)) return URL;
    if (is_path(value)) return PATH;
    return STRING;
}


fn bool is_uuid(String value)
{
    if (value.len != 36) return false;
    return value[8]  == '-' &&
           value[13] == '-' &&
           value[18] == '-' &&
           value[23] == '-';
}

fn bool is_email(String value)
{
    // presence of '@' is a minimal check
    return value.contains("@");
}

fn bool is_ip_address(String value)
{
    // very basic IPv4 heuristic: exactly three dots
    uint dots = 0;
    foreach (c : value) if (c == '.') dots++;
    return dots == 3;
}

fn bool is_url(String value)
{
    return value.starts_with("http://") || value.starts_with("https://");
}

fn bool is_path(String value)
{
    return value.contains("/") || value.contains("\\");
}