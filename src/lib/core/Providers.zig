pub const Provider = struct {
    id: []const u8,
    authorize_url: []const u8,
    token_url: []const u8,
    me_url: []const u8,
    scope: []const u8 = "",
    name_prop: []const u8,
    name_prefix: []const u8 = "",
    id_prop: []const u8 = "id",
    logo: []const u8,
    color: []const u8,
};

fn icon_url(comptime name: []const u8) []const u8 {
    return "https://unpkg.com/simple-icons@" ++ "5.13.0" ++ "/icons/" ++ name ++ ".svg";
}

pub var google = Provider{
    .id = "google",
    .authorize_url = "https://accounts.google.com/o/oauth2/v2/auth",
    .token_url = "https://www.googleapis.com/oauth2/v4/token",
    .me_url = "https://www.googleapis.com/oauth2/v1/userinfo?alt=json",
    .scope = "profile",
    .name_prop = "name",
    .logo = icon_url("google"),
    .color = "#4285F4",
};
