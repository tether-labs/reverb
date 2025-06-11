const std = @import("std");

pub const Self = @This();
name: []const u8,
value: []const u8,
expires: ?i64 = null,
http_only: bool = false,
secure: bool = false,

pub fn init(name: []const u8, value: []const u8, expires: i64) Self {
    return Self{
        .name = name,
        .value = value,
        .expires = expires,
    };
}
