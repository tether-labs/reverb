const std = @import("std");
const Cookie = @import("core/Cookie.zig");
const Context = @import("context.zig");
const mem = std.mem;
const testing = std.testing;
const crypto = std.crypto;
const fmt = std.fmt;
const print = std.debug.print;
const Server = @import("server.zig");
const Ctx_pm = @import("handler.zig").Ctx_pm;
const HttpHeader = @import("core/Header.zig");
const Reply = @import("core/ReplyBuilder.zig");

const ServerError = error{
    HeaderMalformed,
    RequestNotSupported,
    ProtoNotSupported,
    InternalServerError,
    MalformedFormContentType,
};

const CookieTypes = enum {
    // Authorization,
    Session,
};

const RequestTypes = enum {
    OPTIONS,
    GET,
    POST,
    PATCH,
    PUT,
    DELETE,
};

pub const ConnectionTypes = enum {
    Upgrade,
    Keep_Alive,
};

const Header = enum {
    Host,
    @"User-Agent",
    Cookie,
    Accept,
    Upgrade,
    @"Content-Type",
    @"Accept-Language",
    @"Accept-Encoding",
    @"Access-Control-Request-Method",
    @"Access-Control-Request-Headers",
    @"Sec-WebSocket-Key",
    @"Sec-WebSocket-Version",
};

const HeaderCookie = enum {
    Cookie,
};

pub const ContentType = enum {
    None,
    Text,
    Form,
    MultiForm,
    JSON,
};

pub const HTTPHeader = struct {
    request_line: []const u8 = "",
    origin: []const u8 = "",
    host: []const u8 = "",
    accept: []const u8 = "",
    upgrade: []const u8 = "",
    user_agent: []const u8 = "",
    cookie: []const u8 = "",
    cookie_str: []const u8 = "",
    content_type: ContentType = ContentType.None,
    content_length: usize = 0,
    connection: []const u8 = "",
    path: []const u8 = "",
    // cookies: std.ArrayList([]const u8),
    method: []const u8 = "",
    accept_language: []const u8 = "",
    accept_encoding: []const u8 = "",
    accept_control_request_method: []const u8 = "",
    accept_control_request_headers: []const u8 = "",
    boundary: ?[]const u8 = "",
    ws_version: []const u8 = "",
    ws_client_key: []const u8 = "",
    referer: []const u8 = "",

    pub fn init(_: *std.mem.Allocator) !HTTPHeader {
        return HTTPHeader{
            .request_line = undefined,
            .host = undefined,
            .upgrade = undefined,
            .accept = undefined,
            .user_agent = undefined,
            .cookie = undefined,
            // .cookies = std.ArrayList([]const u8).init(arena.*),
            .method = undefined,
            .content_type = ContentType.None,
            .accept_language = undefined,
            .accept_encoding = undefined,
            .accept_control_request_method = null,
            .accept_control_request_headers = undefined,
            .boundary = null,
            .ws_version = undefined,
            .ws_client_key = undefined,
        };
    }

    pub fn deinit(http_header_: *HTTPHeader) void {
        http_header_.cookies.deinit();
    }

    pub fn print(self: HTTPHeader) !void {
        std.debug.print("Req: {s}\nUser: {s}\nHost: {s}\n", .{
            self.request_line,
            self.user_agent,
            self.host,
            self.method,
        });
    }
};

pub fn generateSessionId() ![]const u8 {
    var uuid_buf: [36]u8 = undefined;
    newV4().to_string(&uuid_buf);

    const hash = try convertStringToSlice(&uuid_buf, std.heap.c_allocator);
    return hash;
}

pub fn parseSession(recv_data: []const u8) ![]const u8 {
    const cookie = parseCookie(recv_data);
    if (cookie != null) {
        var cookie_itr = std.mem.splitSequence(u8, cookie.?, "=");
        while (cookie_itr.next()) |line| {
            const cookie_type = std.meta.stringToEnum(CookieTypes, line) orelse continue;
            switch (cookie_type) {
                // .Authorization => {
                //     return convertStringTo16Slice(cookie_itr.peek().?);
                // },
                .Session => {
                    return cookie_itr.peek().?;
                },
            }
            cookie_itr.next();
        }
    }
    return generateSessionId();
}

fn parseCookie(header: []const u8) ?[]const u8 {
    var header_itr = std.mem.tokenizeSequence(u8, header, "\r\n");
    while (header_itr.next()) |line| {
        const name_slice = std.mem.sliceTo(line, ':');
        const header_name = std.meta.stringToEnum(HeaderCookie, name_slice) orelse continue;
        const header_value = std.mem.trimLeft(u8, line[name_slice.len + 1 ..], " ");
        switch (header_name) {
            .Cookie => return header_value,
        }
    }

    return null;
}

fn convertStringTo16Slice(haystack: []const u8) [16]u8 {
    var result: [16]u8 = [_]u8{0} ** 16; // Initialize with zeroes.
    std.mem.copyForwards(u8, result[0..16], haystack[0..16]);
    return result;
}

pub fn parseMethod(request_line: []const u8) ![]const u8 {
    var path_iter = mem.tokenizeScalar(u8, request_line, ' ');
    const method = try matchMethod(&path_iter);
    return method;
}

pub fn parsePath(request_line: []const u8) ![]const u8 {
    var path_iter = mem.tokenizeScalar(u8, request_line, ' ');
    _ = path_iter.next().?;
    const path = path_iter.next().?;
    if (path.len <= 0) return error.NoPath;
    const proto = path_iter.next().?;
    if (!mem.eql(u8, proto, "HTTP/1.1")) return ServerError.ProtoNotSupported;
    return path;
}

pub fn findIndex(haystack: []const u8, needle: u8) ?usize {
    const vec_len = 16;
    const Vec16 = @Vector(16, u8);
    const splt_16: Vec16 = @splat(@as(u8, needle));
    if (haystack.len >= vec_len) {
        var i: usize = 0;
        while (i + vec_len <= haystack.len) : (i += vec_len) {
            const v = haystack[i..][0..vec_len].*;
            const vec: Vec16 = @bitCast(v);
            const mask = vec == splt_16;
            const bits: u16 = @bitCast(mask);
            if (bits != 0) {
                return i + @ctz(bits);
            }
        }
    }
    var i: usize = 0;
    while (i < haystack.len) : (i += 1) {
        if (haystack[i] == needle) return i;
    }
    return null;
}

pub fn findCRLFCRLF(payload: []const u8) ?usize {
    if (payload.len < 4) return null;

    // if (payload.len >= 128) {
    //     // print("We check 128\n", .{});
    //     const V = @Vector(128, u8);
    //     const cr_pattern: V = @splat('\r');
    //     var i: usize = 0;
    //
    //     while (i + 128 <= payload.len) : (i += 128) {
    //         const chunk: V = payload[i..][0..128].*;
    //         const cr_matches = chunk == cr_pattern;
    //         const cr_mask: u128 = @bitCast(cr_matches);
    //
    //         if (cr_mask != 0) {
    //             var mask = cr_mask;
    //             while (mask != 0) {
    //                 const pos = i + @ctz(mask);
    //                 if (pos + 3 < payload.len and
    //                     payload[pos + 1] == '\n' and
    //                     payload[pos + 2] == '\r' and
    //                     payload[pos + 3] == '\n')
    //                 {
    //                     return pos;
    //                 }
    //                 mask &= mask - 1;
    //             }
    //         }
    //     }
    //
    //     // Check remaining bytes after last 128-byte chunk
    //     i -= 3; // Ensure we check overlapping with the last chunk's end
    //     while (i < payload.len - 3) : (i += 1) {
    //         if (payload[i] == '\r' and
    //             payload[i + 1] == '\n' and
    //             payload[i + 2] == '\r' and
    //             payload[i + 3] == '\n')
    //         {
    //             return i;
    //         }
    //     }
    //     return null;
    // }

    if (payload.len >= 64) {
        // print("We check 64\n", .{});
        const V = @Vector(64, u8);
        const cr_pattern: V = @splat('\r');
        var i: usize = 0;

        while (i + 64 <= payload.len) : (i += 64) {
            const chunk: V = payload[i..][0..64].*;
            const cr_matches = chunk == cr_pattern;
            const cr_mask: u64 = @bitCast(cr_matches);

            if (cr_mask != 0) {
                var mask = cr_mask;
                while (mask != 0) {
                    const pos = i + @ctz(mask);
                    if (pos + 3 < payload.len and
                        payload[pos + 1] == '\n' and
                        payload[pos + 2] == '\r' and
                        payload[pos + 3] == '\n')
                    {
                        return pos;
                    }
                    mask &= mask - 1;
                }
            }
        }

        // Check remaining bytes after last 64-byte chunk
        i -= 3; // Ensure we check overlapping with the last chunk's end
        while (i < payload.len - 3) : (i += 1) {
            if (payload[i] == '\r' and
                payload[i + 1] == '\n' and
                payload[i + 2] == '\r' and
                payload[i + 3] == '\n')
            {
                return i;
            }
        }
        return null;
    }

    if (payload.len >= 32) {
        const V = @Vector(32, u8);
        const cr_pattern: V = @splat('\r');
        var i: usize = 0;

        while (i + 32 <= payload.len) : (i += 32) {
            const chunk: V = payload[i..][0..32].*;
            const cr_matches = chunk == cr_pattern;
            const cr_mask: u32 = @bitCast(cr_matches);

            if (cr_mask != 0) {
                var mask = cr_mask;
                while (mask != 0) {
                    const pos = i + @ctz(mask);
                    if (pos + 3 < payload.len and
                        payload[pos + 1] == '\n' and
                        payload[pos + 2] == '\r' and
                        payload[pos + 3] == '\n')
                    {
                        return pos;
                    }
                    mask &= mask - 1;
                }
            }
        }

        // Check remaining bytes after last 32-byte chunk
        i -= 3; // Ensure we check overlapping with the last chunk's end
        while (i < payload.len - 3) : (i += 1) {
            if (payload[i] == '\r' and
                payload[i + 1] == '\n' and
                payload[i + 2] == '\r' and
                payload[i + 3] == '\n')
            {
                return i;
            }
        }
        return null;
    }

    if (payload.len >= 16) {
        const V = @Vector(16, u8);
        const cr_pattern: V = @splat('\r');
        var i: usize = 0;

        while (i + 16 <= payload.len) : (i += 16) {
            const chunk: V = payload[i..][0..16].*;
            const cr_matches = chunk == cr_pattern;
            const cr_mask: u16 = @bitCast(cr_matches);

            if (cr_mask != 0) {
                var mask = cr_mask;
                while (mask != 0) {
                    const pos = i + @ctz(mask);
                    if (pos + 3 < payload.len and
                        payload[pos + 1] == '\n' and
                        payload[pos + 2] == '\r' and
                        payload[pos + 3] == '\n')
                    {
                        return pos;
                    }
                    mask &= mask - 1;
                }
            }
        }

        // Check remaining bytes after last 16-byte chunk
        i -= 3; // Ensure we check overlapping with the last chunk's end
        while (i < payload.len - 3) : (i += 1) {
            if (payload[i] == '\r' and
                payload[i + 1] == '\n' and
                payload[i + 2] == '\r' and
                payload[i + 3] == '\n')
            {
                return i;
            }
        }
        return null;
    }

    // Non-SIMD path for small payloads
    var i: usize = 0;
    while (i <= payload.len - 4) : (i += 1) {
        if (payload[i] == '\r' and
            payload[i + 1] == '\n' and
            payload[i + 2] == '\r' and
            payload[i + 3] == '\n')
        {
            return i;
        }
    }
    return null;
}
// Pre-computed lookup table for header types
const HeaderLookup = struct {
    // First level lookup based on first char
    first_char: [256]u8,

    pub fn init() @This() {
        var table = @This(){
            .first_char = [_]u8{0} ** 256,
        };

        // Initialize with special values for known headers
        table.first_char['G'] = 1; // GET
        table.first_char['P'] = 2; // POST/PATCH
        table.first_char['D'] = 3; // DELETE
        table.first_char['U'] = 4; // UPDATE/User-Agent
        table.first_char['H'] = 5; // Host
        table.first_char['C'] = 6; // Connection/Cookie/Content-Type/Content-Length
        table.first_char['A'] = 7; // Accept-*
        table.first_char['O'] = 8; // Origin
        table.first_char['R'] = 9; // Referer
        table.first_char['S'] = 10; // Referer

        return table;
    }
}.init();

// Pre-allocated buffer for common strings
const CommonStrings = struct {
    get: []const u8 = "GET",
    post: []const u8 = "POST",
    patch: []const u8 = "PATCH",
    delete: []const u8 = "DELETE",
    update: []const u8 = "UPDATE",
    options: []const u8 = "OPTIONS",
};
const commonStrings = CommonStrings{};

/// Find the index of '\r' in the slice. For slices 32 bytes or longer, use a SIMD‐like approach.
const V64 = @Vector(64, u8);
const splt: V64 = @splat(@as(u8, '\r'));

const V32 = @Vector(32, u8);
const splt_32: V32 = @splat(@as(u8, '\r'));
pub fn findCRLF(slice: []const u8) usize {
    if (slice.len >= 64) {
        var i: usize = 0;
        while (i + 64 <= slice.len) : (i += 64) {
            const v = slice[i..][0..64].*;
            const vec: V64 = @bitCast(v);
            const mask = vec == splt;
            const bits: u64 = @bitCast(mask);
            if (bits != 0) {
                return i + @ctz(bits);
            }
        }
    }
    if (slice.len >= 32) {
        var i: usize = 0;
        while (i + 32 <= slice.len) : (i += 32) {
            const v = slice[i..][0..32].*;
            const vec: V32 = @bitCast(v);
            const mask = vec == splt_32;
            const bits: u32 = @bitCast(mask);
            if (bits != 0) {
                return i + @ctz(bits);
            }
        }
    }

    var i: usize = 0;
    while (i < slice.len) : (i += 1) {
        if (slice[i] == '\r') return i;
    }
    return slice.len;
}
// Precomputed method trie (compile-time)
const MethodTrie = struct {
    const masks = [4]u64{
        0x0000_0000_FFFF_FF00, // GET
        0x0000_0000_FFFF_FFFF, // POST
        0x0000_0000_FFFF_FF00, // PUT
        0x0000_0000_FFFF_FF00, // HEAD
    };
    const v1 =
        (@as(u64, 'G') << 0) |
        (@as(u64, 'E') << 8) |
        (@as(u64, 'T') << 16) |
        (@as(u64, ' ') << 24);
    const v2 =
        (@as(u64, 'P') << 0) |
        (@as(u64, 'O') << 8) |
        (@as(u64, 'S') << 16) |
        (@as(u64, 'T') << 24);
    const v3 =
        (@as(u64, 'P') << 0) |
        (@as(u64, 'U') << 8) |
        (@as(u64, 'T') << 16) |
        (@as(u64, ' ') << 24);
    const v4 =
        (@as(u64, 'H') << 0) |
        (@as(u64, 'E') << 8) |
        (@as(u64, 'A') << 16) |
        (@as(u64, 'D') << 24);
    const values = [4]u64{ v1, v2, v3, v4 };
};

var http_header: HTTPHeader = HTTPHeader{};
pub fn parseHeaders(payload: []const u8, ctx_pm: *Ctx_pm) *HTTPHeader {
    // Allocate space for the copy (same length as original)
    var is_first_line = true; // Track if we're on the request line
    var i: usize = 0;
    var line_start: usize = 0;

    if (is_first_line) {
        const header_type = HeaderLookup.first_char[payload[0]];
        switch (header_type) {
            1 => ctx_pm.method = commonStrings.get,
            2 => ctx_pm.method = switch (payload[1]) {
                'O' => commonStrings.post,
                else => commonStrings.patch,
            },
            3 => ctx_pm.method = commonStrings.delete,
            4 => switch (payload[1]) {
                'P' => ctx_pm.method = commonStrings.update,
                else => {},
            },
            else => {},
        }
        // Find CRLF with SIMD+word scan
        const sentinal = findCRLF(payload);

        // Direct path assignment (no copy)
        const value = payload[ctx_pm.method.len + 1 .. sentinal];
        ctx_pm.path = value[0 .. sentinal - 13];

        is_first_line = false;

        i = sentinal + 1;
        line_start = i + 1;
    }

    const last = findCRLFCRLF(payload).?;
    while (i < last) : (i += 1) {
        const c = payload[i];
        if (c != ' ') continue;

        // Quick lookup using pre-computed table
        const header_type = HeaderLookup.first_char[payload[line_start]];
        if (header_type == 0) {
            i = findCRLF(payload[i..]) + i + 1;
            continue;
        }

        const sentinal = findCRLF(payload[i..]) + i;
        const value = payload[i + 1 .. sentinal];

        // Use computed goto pattern for better performance than switch
        switch (header_type) {
            4 => switch (payload[line_start + 1]) {
                's' => http_header.user_agent = value,
                else => {},
            },
            5 => {
                http_header.host = value;
            },
            6 => switch (payload[line_start + 2]) {
                'o' => http_header.cookie_str = value,
                'n' => {
                    switch (payload[line_start + 8]) {
                        // Here we check if we are looking at Content-Type or Content-Length
                        'l', 'L' => {
                            http_header.content_length = std.fmt.parseInt(usize, value, 10) catch 0;
                        },
                        't', 'T' => {
                            type_sw: switch (value[0]) {
                                'a' => {
                                    if (value[12] == 'x') continue :type_sw 'x';
                                    if (value[12] == 'j') continue :type_sw 'j';
                                },
                                't' => {
                                    http_header.content_type = ContentType.Text;
                                },
                                'x' => {
                                    http_header.content_type = ContentType.Form;
                                },
                                'j' => {
                                    http_header.content_type = ContentType.JSON;
                                },
                                'm' => {
                                    http_header.content_type = ContentType.MultiForm;
                                },
                                else => unreachable,
                            }
                        },
                        'o' => {
                            http_header.connection = value;
                        },
                        else => {},
                    }
                },
                else => {},
            },
            7 => if (line_start + 7 < payload.len) switch (payload[line_start + 7]) {
                'L' => http_header.accept_language = value,
                'E' => http_header.accept_encoding = value,
                'C' => if (line_start + 23 < payload.len) switch (payload[line_start + 23]) {
                    'M' => http_header.accept_control_request_method = value,
                    'H' => http_header.accept_control_request_headers = value,
                    else => {},
                },
                else => {},
            },
            8 => switch (payload[line_start + 1]) {
                'r' => {
                    http_header.origin = value;
                },
                'P' => {
                    http_header.method = commonStrings.options;
                },
                else => {},
            },
            9 => http_header.referer = value,
            10 => {
                if (payload[line_start + 4] == 'W') {
                    if (payload[line_start + 14] == 'K') {
                        http_header.ws_client_key = value;
                    }
                }
            },
            else => {},
        }

        i = sentinal + 1;
        line_start = i + 1;
    }

    return &http_header;
}

// var count: usize = 0;
pub fn parseHeader(http_payload: []const u8, ctx_pm: *Ctx_pm) HTTPHeader {
    // _ = @Vector(1024, u8);
    // while (count < http_payload.len) {
    //     _ = http_payload[count];
    //     count += 1;
    // }
    // const http_header = HTTPHeader{};
    // return http_header;
    return parseHeaders(http_payload, ctx_pm);
    // const header_struct = try HTTPHeader.init(arena);
    // var req_parts = mem.tokenizeSequence(u8, http_payload, "\r\n\r\n");
    // _ = req_parts.next() orelse return null;

    // const start_index = findCRLFCRLF(http_payload);

    // const delimiter = "\r\n\r\n";
    // // Find the index of the header terminator
    // _ = std.mem.indexOf(u8, http_payload, delimiter) orelse return null;
    // _ = http_payload[0..delim_index];

    // var header_itr = mem.tokenizeSequence(u8, header, "\r\n");
    // if (mem.indexOf(u8, header_itr.peek().?, "HTTP/1.1") == null) return null;
    // header_struct.request_line = header_itr.next() orelse return ServerError.HeaderMalformed;

    // while (header_itr.next()) |line| {
    //     const name_slice = mem.sliceTo(line, ':');
    //     const header_name = std.meta.stringToEnum(Header, name_slice) orelse continue;
    //     const header_value = mem.trimLeft(u8, line[name_slice.len + 1 ..], " ");
    //     switch (header_name) {
    //         .Host => header_struct.host = header_value,
    //         .Accept => header_struct.accept = header_value,
    //         .Upgrade => {
    //             header_struct.upgrade = header_value;
    //             header_struct.connection = ConnectionTypes.Upgrade;
    //         },
    //         .@"Sec-WebSocket-Key" => header_struct.ws_client_key = header_value,
    //         .@"Sec-WebSocket-Version" => header_struct.ws_version = header_value,
    //         .@"User-Agent" => header_struct.user_agent = header_value,
    //         .Cookie => {
    //             var cookies_split = std.mem.splitSequence(u8, header_value, "; ");
    //             while (cookies_split.next()) |cookie_line| {
    //                 var cookie_split = std.mem.splitSequence(u8, cookie_line, "=");
    //                 while (cookie_split.next()) |cookie_name_or_value| {
    //                     try header_struct.cookies.append(cookie_name_or_value);
    //                 }
    //             }
    //         },
    //         .@"Content-Type" => {
    //             if (mem.eql(u8, header_value, "application/json")) {
    //                 header_struct.content_type = ContentType.JSON;
    //             } else if (mem.eql(u8, header_value, "application/x-www-form-urlencoded")) {
    //                 header_struct.content_type = ContentType.Form;
    //             } else if (mem.startsWith(u8, header_value, "multipart/form-data; boundary=")) {
    //                 header_struct.content_type = ContentType.MultiForm;
    //                 const boundary = header_value[30..];
    //                 header_struct.boundary = boundary;
    //             } else {
    //                 header_struct.content_type = ContentType.None;
    //             }
    //         },
    //         .@"Accept-Language" => header_struct.accept_language = header_value,
    //         .@"Accept-Encoding" => header_struct.accept_encoding = header_value,
    //         .@"Access-Control-Request-Method" => header_struct.accept_control_request_method = header_value,
    //         .@"Access-Control-Request-Headers" => header_struct.accept_control_request_headers = header_value,
    //     }
    // }
    //
}

pub fn parseParams(ctx: *Context, url: []const u8) !?[]const u8 {
    const params_start = findIndex(url, '?') orelse return null;
    // Details
    const lookup_route = url[0..params_start];

    // Loop
    var pos = params_start + 1;
    while (pos < url.len) : (pos += 1) {
        if (ctx.req_params_index >= ctx.params.len) return error.CookieBufferOverflow;
        const param_pair_end = findIndex(url[pos..], '&') orelse {
            // We only have one pair hence we add and return
            const seperator = findIndex(url[pos..], '=') orelse return error.SeperatorNotFound;
            const name = url[pos .. seperator + pos];
            const value = url[seperator + pos + 1 .. url.len];
            ctx.params[ctx.req_params_index] = Context.Param{
                .name = name,
                .value = value,
            };
            ctx.req_params_index += 1;
            return lookup_route;
        };
        // now we find the sperator in this pair and add it to the hashmap and continue on to the next
        // id=123
        const pair = url[pos .. param_pair_end + pos];
        const seperator = findIndex(pair, '=') orelse return error.SeperatorNotFound;
        const name = pair[0..seperator];
        const value = pair[seperator + 1 ..];
        ctx.params[ctx.req_params_index] = Context.Param{
            .name = name,
            .value = value,
        };
        ctx.req_params_index += 1;
        pos += param_pair_end;
    }
    return lookup_route;
}

pub fn parseCookies(ctx: *Context, cookie_str: []const u8) !void {
    // Loop
    var pos: usize = 0;
    while (pos < cookie_str.len) : (pos += 1) {
        if (ctx.req_cookie_index >= ctx.req_cookies.len) return error.CookieBufferOverflow;
        // here we find the cookie end marked by ;
        const cookie_pair_end = findIndex(cookie_str[pos..], ';') orelse {
            // We only have one pair hence we add and return
            const seperator = findIndex(cookie_str[pos..], '=') orelse return error.SeperatorNotFound;
            // this the name of the cookie "oauth_provider=github;"
            // name "oauth_provider;"
            const name = cookie_str[pos .. seperator + pos];
            const value = cookie_str[seperator + pos + 1 .. cookie_str.len];
            ctx.req_cookies[ctx.req_cookie_index] = Cookie{
                .name = name,
                .value = value,
            };
            ctx.req_cookie_index += 1;
            return;
        };
        // now we find the sperator in this pair and add it to the hashmap and continue on to the next
        // id=123
        const pair = cookie_str[pos .. cookie_pair_end + pos];
        const seperator = findIndex(pair, '=') orelse return error.SeperatorNotFound;
        const name = pair[0..seperator];
        const value = pair[seperator + 1 ..];
        ctx.req_cookies[ctx.req_cookie_index] = Cookie{
            .name = name,
            .value = value,
        };

        ctx.req_cookie_index += 1;
        pos += cookie_pair_end;
        pos += 1;
    }
}

fn matchMethod(iter: *mem.TokenIterator(u8, .scalar)) ![]const u8 {
    const method = iter.next().?;
    const method_enum = std.meta.stringToEnum(RequestTypes, method).?;
    switch (method_enum) {
        .OPTIONS => return method,
        .GET => return method,
        .POST => return method,
        .PATCH => return method,
        .DELETE => return method,
        .PUT => return method,
        // else => return ServerError.RequestNotSupported,
    }
}

fn matchDataType(path: []const u8) ![]const u8 {
    var path_iter = mem.tokenizeSequence(u8, path, "/");
    const path_type = path_iter.next();
    if (path_type == null) return error.Null;
    return path_type.?;
}

pub fn httpCodeResponse(proto_name: []const u8, status_code: usize, msg: []const u8, arena: *std.mem.Allocator) ![]const u8 {
    const proto_str = "HTTP/1.1 {d} {s}";
    const proto = std.fmt.allocPrint(
        arena.*,
        proto_str,
        .{
            status_code,
            proto_name,
        },
    ) catch return error.MemoryFull;
    defer arena.free(proto);

    var reply: Reply = undefined;
    try reply.init(arena.*);
    defer reply.deinit();

    try reply.writeHttpProto(proto);

    const max_len = 20;
    var buf: [max_len]u8 = undefined;
    const numAsString = try std.fmt.bufPrint(&buf, "{}", .{msg.len});

    var headers: HttpHeader = undefined;
    headers.init(.{
        .content_length = .{ .override = numAsString },
        .content_type = .{ .override = "text/html; charset=utf8" },
        .connection = .{ .override = "close" },
        .vary = .{ .override = "Origin" },
    });

    var cors = Server.cors;
    try reply.writeHeaders(&headers, &cors);
    try reply.payload(msg);

    const response = try reply.getData();
    return response;
}

pub fn convertStringToSlice(haystack: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const mutable_slice = try allocator.dupe(u8, haystack);
    return mutable_slice;
}

pub const Error = error{InvalidUUID};

pub const UUID = struct {
    bytes: [16]u8,

    pub fn init() UUID {
        var uuid = UUID{ .bytes = undefined };

        crypto.random.bytes(&uuid.bytes);
        // Version 4
        uuid.bytes[6] = (uuid.bytes[6] & 0x0f) | 0x40;
        // Variant 1
        uuid.bytes[8] = (uuid.bytes[8] & 0x3f) | 0x80;
        return uuid;
    }

    pub fn to_string(self: UUID, slice: []u8) void {
        var string: [36]u8 = format_uuid(self);
        std.mem.copyForwards(u8, slice, &string);
    }

    fn format_uuid(self: UUID) [36]u8 {
        var buf: [36]u8 = undefined;
        buf[8] = '-';
        buf[13] = '-';
        buf[18] = '-';
        buf[23] = '-';
        inline for (encoded_pos, 0..) |i, j| {
            buf[i + 0] = hex[self.bytes[j] >> 4];
            buf[i + 1] = hex[self.bytes[j] & 0x0f];
        }
        return buf;
    }

    // Indices in the UUID string representation for each byte.
    const encoded_pos = [16]u8{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };

    // Hex
    const hex = "0123456789abcdef";

    // Hex to nibble mapping.
    const hex_to_nibble = [256]u8{
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    };

    pub fn format(
        self: UUID,
        comptime layout: []const u8,
        options: fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options; // currently unused

        if (layout.len != 0 and layout[0] != 's')
            @compileError("Unsupported format specifier for UUID type: '" ++ layout ++ "'.");

        const buf = format_uuid(self);
        try fmt.format(writer, "{s}", .{buf});
    }

    pub fn parse(buf: []const u8) Error!UUID {
        var uuid = UUID{ .bytes = undefined };

        if (buf.len != 36 or buf[8] != '-' or buf[13] != '-' or buf[18] != '-' or buf[23] != '-')
            return Error.InvalidUUID;

        inline for (encoded_pos, 0..) |i, j| {
            const hi = hex_to_nibble[buf[i + 0]];
            const lo = hex_to_nibble[buf[i + 1]];
            if (hi == 0xff or lo == 0xff) {
                return Error.InvalidUUID;
            }
            uuid.bytes[j] = hi << 4 | lo;
        }

        return uuid;
    }
};

// Zero UUID
pub const zero: UUID = .{ .bytes = .{0} ** 16 };

// Convenience function to return a new v4 UUID.
pub fn newV4() UUID {
    return UUID.init();
}
