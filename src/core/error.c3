module nexlog::errors;
import std::io;

// --- Error kinds ---
enum Error {
    IO_ERROR,
    CONFIG_ERROR,
    BUFFER_ERROR,
    UNEXPECTED,
    ALREADY_INITIALIZED,
}

// --- ErrorContext struct ---
struct ErrorContext {
    String   file;
    uint     line;
    Error    error_type;
    String   message;
    long     timestamp; // unix seconds
}

// --- Core lifecycle function ---
fn ErrorContext ErrorContext.init(self, Error error_type, String message, String file, uint line) @nodiscard
{
    return {
        .error_type = error_type,
        .message    = message,
        .file       = file,
        .line       = line,
        .timestamp  = unix_time_seconds(),
    };
}

// --- Internal: time function ---
extern fn long time(long* t) @private;

fn long unix_time_seconds() @private
{
    return time(null);
}

// --- Helper: print error context ---
fn void print_error_context(ErrorContext ctx)
{
    io::eprintfn(
        "Error[%d] %s:%u: %s - %s",
        ctx.timestamp,
        ctx.file,
        ctx.line,
        error_name(ctx.error_type) @pure,
        ctx.message
    );
}

// --- Helper: map error enum to string ---
fn String error_name(Error e)
{
    switch (e) {
        case IO_ERROR:            return "IOError";
        case CONFIG_ERROR:        return "ConfigError";
        case BUFFER_ERROR:        return "BufferError";
        case UNEXPECTED:          return "Unexpected";
        case ALREADY_INITIALIZED: return "AlreadyInitialized";
    }
}

// --- Error handler type ---
faultdef HANDLER_FAILED;

alias HandlerFn = fn void? (ErrorContext);

struct ErrorHandler {
    HandlerFn handler_fn;
    uint      max_retries;
    uint      retry_delay_ms;
}

// --- Core lifecycle for ErrorHandler ---
fn ErrorHandler ErrorHandler.init(self, HandlerFn handler_fn, uint max_retries, uint retry_delay_ms)
{
    return {
        .handler_fn     = handler_fn,
        .max_retries    = max_retries,
        .retry_delay_ms = retry_delay_ms,
    };
}

// --- Internal: sleep helper ---
struct Timespec @private  { long tv_sec; long tv_nsec; }
extern fn int nanosleep(Timespec* req, Timespec* rem) @private;

fn void sleep_ms(uint ms) @private
{
    Timespec req;
    req.tv_sec  = (long)(ms / 1000);
    req.tv_nsec = (long)((ms % 1000) * 1000000);
    nanosleep(&req, null);
}

// --- Generic function: handle error with retries ---
fn void? handle_error_with_retries(ErrorHandler* self, ErrorContext ctx)
{
    uint retries = 0;
    while (retries < self.max_retries) {
        if (catch self.handler_fn(ctx)) {
            if (retries == self.max_retries - 1) return HANDLER_FAILED?;
            sleep_ms(self.retry_delay_ms);
            retries += 1;
            continue;
        }
        break;
    }
    return;
}

// --- Generic function: default error handler ---
fn void? default_error_handler(ErrorContext ctx)
{
    print_error_context(ctx);
    return;
}
