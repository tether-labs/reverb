const std = @import("std");
const Header = @import("Header.zig");
const Cors = @import("Cors.zig");
const CorsHeaders = Cors.CorsHeaders;
const Headers = Header.Headers;

pub const Reply = @This();
builder: std.ArrayList(u8),

pub fn init(target: *Reply, allocator: std.mem.Allocator) !void {
    const reply_builder = std.ArrayList(u8).init(allocator);
    target.* = .{
        .builder = reply_builder,
    };
}

pub fn deinit(reply: *Reply) void {
    reply.builder.deinit();
}

/// Returns the owned data
pub fn getData(reply: *Reply) ![]const u8 {
    defer reply.builder.deinit();
    return try reply.builder.toOwnedSlice();
}

pub fn writeHttpProto(reply: *Reply, proto: []const u8) !void {
    try reply.builder.appendSlice(proto);
    try reply.builder.appendSlice("\r\n");
}

pub fn writeHeaderPrefix(reply: *Reply, prefix: []const u8) !void {
    try reply.builder.appendSlice(prefix);
}

pub fn writeHeaderValue(reply: *Reply, value: []const u8) !void {
    try reply.builder.appendSlice(value);
    try reply.builder.appendSlice("\r\n");
}

pub fn writeExtraHeaderPrefix(reply: *Reply, prefix: []const u8) !void {
    try reply.builder.appendSlice(prefix);
    try reply.builder.appendSlice(": ");
}

pub fn writeExtraHeaderValue(reply: *Reply, value: []const u8) !void {
    try reply.builder.appendSlice(value);
    try reply.builder.appendSlice("\r\n");
}

pub fn writeHeaders(reply: *Reply, header: *Header, cors: *?Cors) !void {
    if (cors.* != null) {
        try cors.*.?.checkHeaders(reply);
    }
    try header.checkHeaders(reply);
}

pub fn writeCookies(reply: *Reply, cookies_str: []const u8) !void {
    try reply.builder.appendSlice(cookies_str);
}

pub fn payload(reply: *Reply, _payload: []const u8) !void {
    try reply.builder.appendSlice("\r\n");
    try reply.builder.appendSlice(_payload);
}
