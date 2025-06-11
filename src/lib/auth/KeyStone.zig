const std = @import("std");
const print = std.log.debug;
pub const Google = @import("Google.zig");
pub const Github = @import("Github.zig");
const Context = @import("../context.zig");
const Cookie = @import("../core/Cookie.zig");
const QueryBuilder = @import("../core/oauth/QueryBuilder.zig");
const JWT = @import("../core/JWT.zig");
pub const JWT_SECRET = "37fe35bd1e029d247251b560c2d2cf2866834577d0166c221e2852bab8e5f3710dc055fe2b413b52a6e3d8f017711f7bf652e462be5dbbd041e7237748b3f267";

const Secrets = struct {
    github: ?[]const u8 = null,
    google: ?[]const u8 = null,
    apple: ?[]const u8 = null,
    azure: ?[]const u8 = null,
};

const ClientIds = struct {
    github: ?[]const u8 = null,
    google: ?[]const u8 = null,
    apple: ?[]const u8 = null,
    azure: ?[]const u8 = null,
};

const Config = struct {
    client_ids: ClientIds,
    secrets: Secrets,
};

const KeyStone = @This();
pub var keystone_config: Config = undefined;
var google_options: Google.Options = undefined;
var google_provider: Google.Provider = undefined;
var github_options: Github.Options = undefined;
var github_provider: Github.Provider = undefined;

pub fn init(config: Config, allocator: *std.mem.Allocator) !void {
    keystone_config = config;

    if (keystone_config.client_ids.google != null and keystone_config.secrets.google != null) {
        const client_id = keystone_config.client_ids.google orelse return error.ClientIdNull;
        const secret = keystone_config.secrets.google orelse return error.ClientSecretNull;
        google_options = Google.Options{
            .client_id = client_id,
            .client_secret = secret,
            .redirect_uri = "http://localhost:5173/nightwatch/auth",
            .grant_type = "authorization_code",
        };
        try google_provider.init(google_options, allocator);
    }
    if (keystone_config.client_ids.github != null and keystone_config.secrets.github != null) {
        const client_id = keystone_config.client_ids.github orelse return error.ClientIdNull;
        const secret = keystone_config.secrets.github orelse return error.ClientSecretNull;
        github_options = Github.Options{
            .client_id = client_id,
            .client_secret = secret,
            .redirect_uri = "http://localhost:5173/nightwatch/auth",
        };
        try github_provider.init(github_options, allocator);
    }
}

const OauthProvider = enum {
    google,
    apple,
    github,
    azure,
};

pub fn refreshToken(provider: OauthProvider, refresh_token: []const u8) ![]const u8 {
    switch (provider) {
        .google => {
            return try google_provider.refreshToken(refresh_token);
        },
        .github => {
            return try github_provider.refreshToken(refresh_token);
        },
        else => {},
    }
    return error.InValidProvider;
}

pub fn getUserInfo(provider: OauthProvider, access_token: []const u8) ![]const u8 {
    switch (provider) {
        .google => {
            return try google_provider.getUserInfo(access_token);
        },
        .github => {
            return try github_provider.getUserInfo(access_token);
        },
        else => {},
    }
    return error.InValidProvider;
}



// Login with google
// send auth-code
// receive code and exchange for access and refresh token
// store refresh token in db hashed
// set cookie with refresh token
// compare with cookie token on request
pub fn exchangeGoogleToken(ctx: *Context) !*Google.TokenResp {
    // Parse auth code
    // parse the form to get the auth-code
    ctx.parseForm() catch |err| {
        return err;
    };
    const auth_code = ctx.form_params.get("auth-code") orelse return error.AuthCodeNull;
    // we create the google options

    // Get Google JWT
    const body: []const u8 = google_provider.tokenExchange(auth_code) catch |err| {
        return err;
    };
    const resp: *Google.TokenResp = try Google.parseResp(Google.TokenResp, body, ctx.arena);
    return resp;
}

// Login with github
// send auth-code
// receive code and exchange for access and refresh token
// store refresh token in db hashed
// set cookie with refresh token
// compare with cookie token on request
pub fn exchangeGithubToken(ctx: *Context) ![]const u8 {
    // Parse auth code
    ctx.parseForm() catch |err| {
        print("Parse Form: {any}\n", .{err});
        try ctx.ERROR(404, "Failed To Parse Form");
        return;
    };
    const auth_code = ctx.form_params.get("auth-code").?;

    const body: []const u8 = github_provider.tokenExchange(auth_code) catch |err| {
        print("Github Error: {any}\n", .{err});
        try ctx.ERROR(404, "Failed To Exchange");
        return error.TokenExchangeGithub;
    };

    const map = try QueryBuilder.parseParams(body, ctx.arena) orelse return error.ParsingParams;
    const access_token = map.get("access_token") orelse return error.GetAccessToken;
    return access_token;

    // const resp: *GithubTokenResp = try parseResp(GithubTokenResp, body, ctx.arena);
}
