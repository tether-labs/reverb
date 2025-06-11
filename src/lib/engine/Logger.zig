// [timestamp] [log_type] [file] string
const std = @import("std");

pub const Logger = @This();
mutex: std.Thread.Mutex,

const LogLevel = enum {
    DEBUG,
    WARN,
    FATAL,
    INFO,
    ERROR,

    pub fn color(log_level: LogLevel) []const u8 {
        return switch (log_level) {
            .DEBUG => "\x1b[36m", // Cyan
            .INFO => "\x1b[32m", // Green
            .WARN => "\x1b[33m", // Yellow
            .ERROR => "\x1b[31m", // Red
            .FATAL => "\x1b[35m", // Magenta
        };
    }
};

pub fn init(target: *Logger) void {
    target.* = .{
        .mutex = .{},
    };
}

fn log(
    logger: *Logger,
    log_level: LogLevel,
    comptime fmt: []const u8,
    args: anytype,
    opt_src: ?std.builtin.SourceLocation,
) !void {
    logger.mutex.lock();
    defer logger.mutex.unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print("[{d}] ", .{std.time.timestamp()}) catch return;
    nosuspend stderr.print("[{s}{s}\x1b[0m] ", .{ log_level.color(), @tagName(log_level) }) catch return;
    if (opt_src) |src| {
        nosuspend stderr.print("[{s}:{d}] => ", .{ src.file, src.line }) catch return;
    }
    nosuspend stderr.print(fmt, args) catch return;
    nosuspend stderr.print("\n", .{}) catch return;
}

pub fn warn(
    logger: *Logger,
    comptime fmt: []const u8,
    args: anytype,
    opt_src: ?std.builtin.SourceLocation,
) !void {
    try logger.log(LogLevel.WARN, fmt, args, opt_src);
}
pub fn debug(
    logger: *Logger,
    comptime fmt: []const u8,
    args: anytype,
    opt_src: ?std.builtin.SourceLocation,
) !void {
    try logger.log(LogLevel.DEBUG, fmt, args, opt_src);
}
pub fn fatal(
    logger: *Logger,
    comptime fmt: []const u8,
    args: anytype,
    opt_src: ?std.builtin.SourceLocation,
) !void {
    try logger.log(LogLevel.FATAL, fmt, args, opt_src);
}
pub fn info(
    logger: *Logger,
    comptime fmt: []const u8,
    args: anytype,
    opt_src: ?std.builtin.SourceLocation,
) !void {
    try logger.log(LogLevel.INFO, fmt, args, opt_src);
}
pub fn err(
    logger: *Logger,
    comptime fmt: []const u8,
    args: anytype,
    opt_src: ?std.builtin.SourceLocation,
) !void {
    try logger.log(LogLevel.ERROR, fmt, args, opt_src);
}

test "all logs" {
    var logger: Logger = undefined;
    logger.init();
    try logger.warn("Panic in the building {s}", .{"Escape now🔥"});
    try logger.debug("Here are the logs for age {d}", .{24});
    try logger.info("INFO {s}", .{"accessining"});
    try logger.err("ERROR {s}", .{"accessining"});
    try logger.fatal("FATAL {s}", .{"accessining"});
    const vec1: @Vector(5, i32) = .{ 1, 2, 3, 4, 5 };
    const vec2: @Vector(5, i32) = .{ 6, 7, 8, 9, 10 };
    try logger.info("INFO {any}", .{vec1 + vec2});
}
