const std = @import("std");
const ReplyBuilder = @import("ReplyBuilder.zig");

pub const Header = @This();
headers: Headers,

pub const ExtraHeader = struct { key: []const u8, value: []const u8 };
pub const Headers = struct {
    host: Value = .default,
    vary: Value = .default,
    authorization: Value = .default,
    user_agent: Value = .default,
    connection: Value = .default,
    accept_encoding: Value = .default,
    content_type: Value = .default,
    content_length: Value = .default,
    extra_headers: ?[]const ExtraHeader = null,

    pub const Value = union(enum) {
        default,
        omit,
        override: []const u8,
    };
};

pub fn init(target: *Header, headers: Headers) void {
    target.* = .{ .headers = headers };
}

pub fn checkHeaders(header: *Header, reply_builder: *ReplyBuilder) !void {
    if (try emitOverridableHeader("Host: ", header.headers.host, reply_builder)) {
        // The default is to omit content-type if not provided because
        // "application/octet-stream" is redundant.
    }
    if (try emitOverridableHeader("Vary: ", header.headers.vary, reply_builder)) {
        // The default is to omit content-type if not provided because
        // "application/octet-stream" is redundant.
    }
    if (try emitOverridableHeader("Authorization: ", header.headers.authorization, reply_builder)) {
        // The default is to omit content-type if not provided because
        // "application/octet-stream" is redundant.
    }
    if (try emitOverridableHeader("User-Agent: ", header.headers.user_agent, reply_builder)) {
        // The default is to omit content-type if not provided because
        // "application/octet-stream" is redundant.
    }
    if (try emitOverridableHeader("Connection: ", header.headers.connection, reply_builder)) {
        try reply_builder.writeHeaderPrefix("Connection: ");
        try reply_builder.writeHeaderValue("close");
        // The default is to omit content-type if not provided because
        // "application/octet-stream" is redundant.
    }
    if (try emitOverridableHeader("Accept-Encoding: ", header.headers.accept_encoding, reply_builder)) {
        // The default is to omit content-type if not provided because
        // "application/octet-stream" is redundant.
    }
    if (try emitOverridableHeader("Content-Type: ", header.headers.content_type, reply_builder)) {
        try reply_builder.writeHeaderPrefix("Content-Type: ");
        try reply_builder.writeHeaderValue("text/html; charset=utf8");
        // The default is to omit content-type if not provided because
        // "application/octet-stream" is redundant.
    }
    if (try emitOverridableHeader("Content-Length: ", header.headers.content_length, reply_builder)) {
        try reply_builder.writeHeaderPrefix("Content-Length: ");
        try reply_builder.writeHeaderValue("0");
        // The default is to omit content-type if not provided because
        // "application/octet-stream" is redundant.
    }

    if (header.headers.extra_headers) |extra_headers| {
        for (extra_headers) |exh| {
            try reply_builder.writeExtraHeaderPrefix(exh.key);
            try reply_builder.writeExtraHeaderValue(exh.value);
        }
    }
}

/// Returns true if the default behavior is required, otherwise handles
/// writing (or not writing) the header.
fn emitOverridableHeader(prefix: []const u8, v: Headers.Value, reply_builder: *ReplyBuilder) !bool {
    switch (v) {
        .default => return true,
        .omit => return false,
        .override => |x| {
            try reply_builder.writeHeaderPrefix(prefix);
            try reply_builder.writeHeaderValue(x);
            return false;
        },
    }
}
