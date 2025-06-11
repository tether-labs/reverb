const std = @import("std");
const print = std.log.debug;
const Context = @import("../context.zig");
const QueryBuilder = @import("../core/oauth/QueryBuilder.zig");
const JWT = @import("../core/JWT.zig");
const http = std.http;
const json = std.json;

pub const User = struct {
    login: []const u8,
    id: u64,
    node_id: []const u8,
    avatar_url: []const u8,
    gravatar_id: []const u8,
    url: []const u8,
    html_url: []const u8,
    followers_url: []const u8,
    following_url: []const u8,
    gists_url: []const u8,
    starred_url: []const u8,
    subscriptions_url: []const u8,
    organizations_url: []const u8,
    repos_url: []const u8,
    events_url: []const u8,
    received_events_url: []const u8,
    type: []const u8,
    user_view_type: []const u8,
    site_admin: bool,
    name: ?[]const u8,
    company: ?[]const u8,
    blog: []const u8,
    location: ?[]const u8,
    email: ?[]const u8,
    hireable: ?bool,
    bio: ?[]const u8,
    twitter_username: ?[]const u8,
    notification_email: ?[]const u8,
    public_repos: u32,
    public_gists: u32,
    followers: u32,
    following: u32,
    created_at: []const u8,
    updated_at: []const u8,
    private_gists: u32,
    total_private_repos: u32,
    owned_private_repos: u32,
    disk_usage: u64,
    collaborators: u32,
    two_factor_authentication: bool,
    plan: Plan,

    pub const Plan = struct {
        name: []const u8,
        space: u64,
        collaborators: u32,
        private_repos: u32,
    };
};

pub const Options = struct {
    client_id: []const u8,
    client_secret: []const u8,
    redirect_uri: []const u8 = "http://localhost:5173/nightwatch/auth",
    state: []const u8 = "random_csrf_token",
};

pub const Provider = struct {
    const Self = @This();
    options: Options,
    query: QueryBuilder,
    arena: *std.mem.Allocator,
    access_token: ?[]const u8 = null,

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

    pub fn tokenExchange(github_prov: *Self, auth_code: []const u8) ![]const u8 {
        try github_prov.query.add("client_id", github_prov.options.client_id);
        try github_prov.query.add("client_secret", github_prov.options.client_secret);
        try github_prov.query.add("code", auth_code);
        try github_prov.query.add("redirect_uri", github_prov.options.redirect_uri); // or your actual callback URL
        try github_prov.query.add("state", github_prov.options.state);
        defer github_prov.query.clear();
        //
        try github_prov.query.queryStrEncode();
        const full_url = try github_prov.query.generateUrl("https://github.com/login/oauth/access_token", github_prov.query.str);
        defer github_prov.arena.free(full_url);

        const uri = try std.Uri.parse(full_url);

        // Make the request
        var buf: [4096]u8 = undefined;
        var client = http.Client{ .allocator = github_prov.arena.* };

        var req = try client.open(.POST, uri, http.Client.RequestOptions{
            .server_header_buffer = &buf,
            .headers = http.Client.Request.Headers{
                .content_type = .{ .override = "application/json" },
            },
        });

        req.transfer_encoding = .{ .content_length = 0 };
        defer req.deinit();

        _ = try req.send();
        _ = try req.finish();
        _ = try req.wait();

        var rdr = req.reader();
        const body = try rdr.readAllAlloc(github_prov.arena.*, 1024 * 1024 * 4);
        // Check the HTTP return code
        if (req.response.status != std.http.Status.ok) {
            std.debug.print("\nBody: {s}\n", .{body});
            std.debug.print("\nStatus: {any}\n", .{req.response.status});
            std.debug.print("\nReason: {s}\n", .{req.response.reason});

            const ErrorStruct = struct {
                @"error": []const u8,
                error_description: []const u8,
            };

            _ = try parseResp(ErrorStruct, body, github_prov.arena);

            return error.WrongStatusResponse;
        }
        return body;
    }

    pub fn getUserInfo(github_prov: *Self, access_token: []const u8) ![]const u8 {
        if (github_prov.access_token == null) return error.AccessTokenNull;
        var allocator = std.heap.c_allocator;
        const authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{access_token});
        defer allocator.free(authorization);
        const uri = try std.Uri.parse("https://api.github.com/user");
        // Make the request
        var buf: [4096]u8 = undefined;
        var client = http.Client{ .allocator = github_prov.arena.* };

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
        const body = try rdr.readAllAlloc(github_prov.arena.*, 1024 * 1024 * 4);
        // Check the HTTP return code
        if (req.response.status != std.http.Status.ok) {
            std.debug.print("\nBody: {s}\n", .{body});
            std.debug.print("\nStatus: {any}\n", .{req.response.status});
            std.debug.print("\nReason: {s}\n", .{req.response.reason});

            const ErrorStruct = struct {
                @"error": []const u8,
                error_description: []const u8,
            };

            _ = try parseResp(ErrorStruct, body, github_prov.arena);

            return error.WrongStatusResponse;
        }
        return body;
    }

    // Opening up a a http.Client.open cause slower compile time
    pub fn refreshToken(github_prov: *Self, refresh_token: []const u8) ![]const u8 {
        try github_prov.query.add("client_id", github_prov.options.client_id);
        try github_prov.query.add("client_secret", github_prov.options.client_secret);
        try github_prov.query.add("refresh_token", refresh_token); // or your actual callback URL
        try github_prov.query.add("redirect_uri", github_prov.options.redirect_uri); // or your actual callback URL
        try github_prov.query.add("state", github_prov.options.state);
        defer github_prov.query.clear();
        //
        // try github_prov.query.add("grant_type", github_prov.options.grant_type);
        //
        try github_prov.query.queryStrEncode();
        const full_url = try github_prov.query.generateUrl("https://oauth2.githubapis.com/token", github_prov.query.str);
        defer github_prov.arena.free(full_url);

        const uri = try std.Uri.parse(full_url);

        // Make the request
        var buf: [4096]u8 = undefined;
        var client = http.Client{ .allocator = github_prov.arena.* };

        var req = try client.open(.POST, uri, http.Client.RequestOptions{
            .server_header_buffer = &buf,
            .headers = http.Client.Request.Headers{
                .content_type = .{ .override = "application/json" },
            },
        });
        defer req.deinit();

        _ = try req.send();
        _ = try req.finish();
        _ = try req.wait();

        var rdr = req.reader();
        const body = try rdr.readAllAlloc(github_prov.arena.*, 1024 * 1024 * 4);

        // Check the HTTP return code
        if (req.response.status != std.http.Status.ok) {
            return error.WrongStatusResponse;
        }

        return body;
    }
};

pub const TokenResp = struct {
    access_token: []const u8,
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


