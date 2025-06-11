const std = @import("std");
const print = std.log.debug;
const Context = @import("../context.zig");
const QueryBuilder = @import("QueryBuilder.zig");
const JWT = @import("../core/JWT.zig");
const http = std.http;
const json = std.json;

pub const Options = struct {
    client_id: []const u8,
    client_secret: []const u8,
    redirect_uri: []const u8 = "http://localhost:5173/nightwatch/auth",
    grant_type: []const u8 = "authorization_code",
};

pub const GoogleUserInfo = struct {
    sub: []const u8,
    name: []const u8,
    given_name: []const u8,
    family_name: []const u8,
    picture: []const u8,
    email: []const u8,
    email_verified: bool,
};

pub const Provider = struct {
    const Self = @This();
    options: Options,
    query: QueryBuilder,
    arena: *std.mem.Allocator,

    pub fn init(
        target: *Provider,
        options: Options,
        allocator: *std.mem.Allocator,
    ) !void {
        var query: QueryBuilder = undefined;
        try query.init(allocator.*);
        target.* = .{
            .options = options,
            .query = query,
            .arena = allocator,
        };
    }
    pub fn deinit(self: *Self) void {
        self.query.deinit();
    }

    pub fn tokenExchange(google_prov: *Self, auth_code: []const u8) ![]const u8 {
        try google_prov.query.add("code", auth_code);
        try google_prov.query.add("client_id", google_prov.options.client_id);
        try google_prov.query.add("client_secret", google_prov.options.client_secret);
        try google_prov.query.add("redirect_uri", google_prov.options.redirect_uri); // or your actual callback URL
        try google_prov.query.add("grant_type", google_prov.options.grant_type);
        defer google_prov.query.clear();
        //
        try google_prov.query.queryStrEncode();
        const full_url = try google_prov.query.generateUrl("https://oauth2.googleapis.com/token", google_prov.query.str);
        defer google_prov.arena.free(full_url);

        const uri = try std.Uri.parse(full_url);

        // Make the request
        var buf: [1024]u8 = undefined;
        var client = http.Client{ .allocator = google_prov.arena.* };

        var req = try client.open(.POST, uri, .{
            .server_header_buffer = &buf,
            .headers = .{
                .content_type = .{ .override = "application/x-www-form-urlencoded" },
            },
        });

        req.transfer_encoding = .{ .content_length = 0 };
        defer req.deinit();

        _ = try req.send();
        _ = try req.finish();
        _ = try req.wait();

        var rdr = req.reader();
        const body = try rdr.readAllAlloc(google_prov.arena.*, 1024 * 1024 * 4);
        // Check the HTTP return code
        if (req.response.status != std.http.Status.ok) {
            std.debug.print("\nBody: {s}\n", .{body});
            std.debug.print("\nStatus: {any}\n", .{req.response.status});
            std.debug.print("\nReason: {s}\n", .{req.response.reason});

            const ErrorStruct = struct {
                @"error": []const u8,
                error_description: []const u8,
            };

            _ = try parseResp(ErrorStruct, body, google_prov.arena);

            return error.WrongStatusResponse;
        }
        return body;
    }

    pub fn getUserInfo(google_prov: *Self, access_token: []const u8) ![]const u8 {
        var allocator = std.heap.c_allocator;
        const authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{access_token});
        defer allocator.free(authorization);
        const uri = try std.Uri.parse("https://openidconnect.googleapis.com/v1/userinfo");
        // Make the request
        var buf: [4096]u8 = undefined;
        var client = http.Client{ .allocator = google_prov.arena.* };

        var req = try client.open(.GET, uri, http.Client.RequestOptions{
            .server_header_buffer = &buf,
            .headers = http.Client.Request.Headers{
                .authorization = .{ .override = authorization },
                .user_agent = .{ .override = "Nightwatch" },
            },
        });

        defer req.deinit();

        _ = try req.send();
        _ = try req.finish();
        _ = try req.wait();

        var rdr = req.reader();
        const body = try rdr.readAllAlloc(google_prov.arena.*, 1024 * 1024 * 4);
        // Check the HTTP return code
        if (req.response.status != std.http.Status.ok) {
            std.debug.print("\nBody: {s}\n", .{body});
            std.debug.print("\nStatus: {any}\n", .{req.response.status});
            std.debug.print("\nReason: {s}\n", .{req.response.reason});

            const ErrorStruct = struct {
                @"error": []const u8,
                error_description: []const u8,
            };

            _ = try parseResp(ErrorStruct, body, google_prov.arena);

            return error.WrongStatusResponse;
        }
        return body;
    }

    // Opening up a a http.Client.open cause slower compile time
    pub fn refreshToken(google_prov: *Self, refresh_token: []const u8) ![]const u8 {
        try google_prov.query.add("client_id", google_prov.options.client_id);
        try google_prov.query.add("client_secret", google_prov.options.client_secret);
        try google_prov.query.add("refresh_token", refresh_token); // or your actual callback URL
        try google_prov.query.add("grant_type", "refresh_token");
        defer google_prov.query.clear();
        //
        try google_prov.query.queryStrEncode();
        const full_url = try google_prov.query.generateUrl("https://oauth2.googleapis.com/token", google_prov.query.str);
        defer google_prov.arena.free(full_url);

        const uri = try std.Uri.parse(full_url);

        // Make the request
        var buf: [1024]u8 = undefined;
        var client = http.Client{ .allocator = google_prov.arena.* };

        var req = try client.open(.POST, uri, .{
            .server_header_buffer = &buf,
            .headers = .{
                .content_type = .{ .override = "application/x-www-form-urlencoded" },
            },
        });

        req.transfer_encoding = .{ .content_length = 0 };
        defer req.deinit();

        _ = try req.send();
        _ = try req.finish();
        _ = try req.wait();

        var rdr = req.reader();
        const body = try rdr.readAllAlloc(google_prov.arena.*, 1024 * 1024 * 4);
        // Check the HTTP return code
        if (req.response.status != std.http.Status.ok) {
            std.log.err("\nBody: {s}\n", .{body});
            std.log.err("\nStatus: {any}\n", .{req.response.status});
            std.log.err("\nReason: {s}\n", .{req.response.reason});

            const ErrorStruct = struct {
                @"error": []const u8,
                error_description: []const u8,
            };

            _ = try parseResp(ErrorStruct, body, google_prov.arena);

            return error.WrongStatusResponse;
        }
        return body;
    }
};

pub const TokenResp = struct {
    access_token: []const u8,
    token_type: []const u8,
    expires_in: i64,
    refresh_token: ?[]const u8,
    scope: ?[]const u8,
    id_token: ?[]const u8,
};

pub const RefreshTokenResp = struct {
    access_token: []const u8,
    token_type: []const u8,
    expires_in: i64,
    scope: ?[]const u8,
    id_token: ?[]const u8,
};

pub fn parseResp(comptime T: type, body: []const u8, allocator: *std.mem.Allocator) !*T {
    const index = std.mem.indexOf(u8, body, "{").?;
    const binded_value: *T = try allocator.create(T);
    const parsed = json.parseFromSlice(
        T,
        allocator.*,
        body[index..body.len],
        .{},
    ) catch return error.MalformedJson;
    defer parsed.deinit();

    binded_value.* = parsed.value;
    return binded_value;
}

pub const TokenResponse = struct {
    access_token: []const u8,
    token_type: []const u8,
    expires_in: i64,
    refresh_token: ?[]const u8,
    scope: ?[]const u8,
    id_token: ?[]const u8,

    pub fn deinit(self: *const TokenResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.access_token);
        allocator.free(self.token_type);
        if (self.refresh_token) |rt| allocator.free(rt);
        if (self.scope) |s| allocator.free(s);
        if (self.id_token) |it| allocator.free(it);
    }
};
