const std = @import("std");
const print = std.debug.print;
const jwt_id = "eyJhbGciOiJSUzI1NiIsImtpZCI6IjYzMzdiZTYzNjRmMzgyNDAwOGQwZTkwMDNmNTBiYjZiNDNkNWE5YzYiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20iLCJhenAiOiI4NjgwNjE0MzYyNjAtNGlybWd2Z2hxbTgxMDdpMjFpb2RyODhyOHV1MTBnNXUuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJhdWQiOiI4NjgwNjE0MzYyNjAtNGlybWd2Z2hxbTgxMDdpMjFpb2RyODhyOHV1MTBnNXUuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdWIiOiIxMDg2NDQ4Nzg3MDcwNDM3NjI5NDgiLCJlbWFpbCI6InYucm9reC5uZWxsZW1hbm5AZ21haWwuY29tIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsImF0X2hhc2giOiIzOXZpYkVJM0NfV3FYMmtFcmZ0UTBRIiwibmFtZSI6IlZpYy1BdWd1c3QgUm9reC1OZWxsZW1hbm4iLCJwaWN0dXJlIjoiaHR0cHM6Ly9saDMuZ29vZ2xldXNlcmNvbnRlbnQuY29tL2EvQUNnOG9jSlJRZFhHOVd5UGNubDllZjdBSFhjUkZ0REFJLVNXWURGeXNySHNoZGtGaW9IeG45WT1zOTYtYyIsImdpdmVuX25hbWUiOiJWaWMtQXVndXN0IiwiZmFtaWx5X25hbWUiOiJSb2t4LU5lbGxlbWFubiIsImlhdCI6MTczNzQ5NjUwNywiZXhwIjoxNzM3NTAwMTA3fQ.SUiA-TxTAapA3BzEv68gBSUC0tZ_tatxcd-sHc9MA_A1n7XN1VRrW4kHmUA2o3vL9Fi3y6CjI9yaYKS6jhsYddesfKDwG_YGF1SKRNDMAF6ROs_ZIDnWVxzpu3wUl3MhOzDEPh2M1Wii0PnPVim5NaJFEhnuYSzJpRQI_2s_jMAs-QfTYXx0pG4vtJJaGYTloXwmsiKEXpT-F0fAPMBVFUaDLYM9SMy4ztrR2ZbupTIe1a7lG1T5nJlec5j3KdfQZWqV5wCZ_SNq79fzVbndB71sHfdwBoScqjJeFBGTrA_Y_GM2PIa2u-HduZviJ7Eki2n95IzUvYBj7GDZUfUDbg";

pub const JWT2 = struct {
    header: []const u8,
    payload: []const u8,
    signature: []const u8,
};

pub const JwtError = error{
    InvalidFormat,
    InvalidBase64,
    InvalidJson,
    InvalidSignature,
};

pub const JwtHeader = struct {
    alg: []const u8,
    typ: []const u8,
};

// Define the Header struct
pub const Header = struct {
    alg: []const u8, // Algorithm (e.g., "RS256")
    kid: []const u8, // Key ID
    typ: []const u8, // Type (e.g., "JWT")
};

// Define the Payload struct
pub const Payload = struct {
    iss: []const u8, // Issuer
    azp: []const u8, // Authorized party
    aud: []const u8, // Audience
    sub: []const u8, // Subject
    email: []const u8, // Email
    email_verified: bool, // Email verified status
    at_hash: []const u8, // Access token hash
    name: []const u8, // Full name
    picture: []const u8, // Profile picture URL
    given_name: []const u8, // Given name
    family_name: []const u8, // Family name
    iat: i64, // Issued at (timestamp)
    exp: i64, // Expiration time (timestamp)
};

pub fn decodev2(token: []const u8, allocator: *std.mem.Allocator) !JWT2 {
    var jwt_itr = std.mem.splitScalar(u8, token, '.');

    const header = jwt_itr.next().?;
    const payload = jwt_itr.next().?;
    const signature = jwt_itr.next().?;

    // Initialize the Base64Url decoder
    var decoder = std.base64.Base64Decoder.init(
        std.base64.url_safe_alphabet_chars,
        null, // Use '=' as pad_char if padding is present, otherwise use null
    );

    // Decode the header
    var header_decoded: [256]u8 = undefined;
    decoder.decode(header_decoded[0..], header) catch |err| {
        std.debug.print("Failed to decode header: {}\n", .{err});
        return err;
    };

    const header_len = try decoder.calcSizeForSlice(header);

    // Decode the payload
    var payload_decoded: [1024]u8 = undefined;
    decoder.decode(payload_decoded[0..], payload) catch |err| {
        std.debug.print("Failed to decode payload: {}\n", .{err});
        return err;
    };

    const payload_len = try decoder.calcSizeForSlice(payload);

    // Decode the signature
    var signature_decoded: [1024]u8 = undefined;
    decoder.decode(signature_decoded[0..], signature) catch |err| {
        std.debug.print("Failed to decode signature: {}\n", .{err});
        return err;
    };

    const signature_len = try decoder.calcSizeForSlice(signature);

    // // Print the signature as raw bytes (hex format for readability)
    // std.debug.print("\nSignature (hex): ", .{});
    // for (signature_decoded[0..signature_len]) |byte| {
    //     std.debug.print("{x:0>2} ", .{byte});
    // }

    const alloc_header = try std.fmt.allocPrint(allocator.*, "{s}", .{header_decoded[0..header_len]});
    const alloc_payload = try std.fmt.allocPrint(allocator.*, "{s}", .{payload_decoded[0..payload_len]});
    const alloc_signature = try std.fmt.allocPrint(allocator.*, "{s}", .{signature_decoded[0..signature_len]});

    return JWT2{
        .header = alloc_header,
        .payload = alloc_payload,
        .signature = alloc_signature,
    };
}

const Algorithm = @import("root.zig").Algorithm;
const HeaderRoot = @import("root.zig").Header;
const Validation = @import("root.zig").Validation;

/// Key used for decoding JWT tokens
pub const DecodingKey = union(enum) {
    secret: []const u8,
    edsa: std.crypto.sign.Ed25519.PublicKey,
    es256: std.crypto.sign.ecdsa.EcdsaP256Sha256.PublicKey,
    es384: std.crypto.sign.ecdsa.EcdsaP384Sha384.PublicKey,
    //rsa: std.crypto.Certificate.rsa.PublicKey,

    fn fromSecret(secret: []const u8) @This() {
        return .{ .secret = secret };
    }

    fn fromEdsaBytes(bytes: [std.crypto.sign.Ed25519.PublicKey]u8) !@This() {
        return .{ .edsa = try std.crypto.sign.Ed25519.PublicKey.fromBytes(bytes) };
    }

    pub fn fromEs256Bytes(bytes: [std.crypto.ecdsa.EcdsaP256Sha256.PublicKey.encoded_length]u8) !@This() {
        return .{ .es256 = try std.crypto.sign.ecdsa.EcdsaP256Sha256.PublicKey.fromBytes(bytes) };
    }

    pub fn fromEs384Bytes(bytes: [std.crypto.ecdsa.EcdsaP384Sha384.PublicKey.encoded_length]u8) !@This() {
        return .{ .es384 = try std.crypto.sign.ecdsa.EcdsaP384Sha384.PublicKey.fromBytes(bytes) };
    }
};

fn decodePart(allocator: std.mem.Allocator, comptime T: type, encoded: []const u8) !T {
    const decoder = std.base64.url_safe_no_pad.Decoder;
    const dest = try allocator.alloc(u8, try decoder.calcSizeForSlice(encoded));
    _ = try decoder.decode(dest, encoded);
    return try std.json.parseFromSliceLeaky(T, allocator, dest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

pub fn JWT(comptime ClaimSet: type) type {
    return struct {
        arena: *std.heap.ArenaAllocator,
        header: HeaderRoot,
        claims: ClaimSet,

        pub fn deinit(self: *@This()) void {
            const child = self.arena.child_allocator;
            self.arena.deinit();
            child.destroy(self.arena);
        }
    };
}

pub fn decode(
    allocator: std.mem.Allocator,
    comptime ClaimSet: type,
    str: []const u8,
    key: DecodingKey,
    validation: Validation,
) !JWT(ClaimSet) {
    var arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer {
        arena.deinit();
        allocator.destroy(arena);
    }
    if (std.mem.count(u8, str, ".") == 2) {
        const sigSplit = std.mem.lastIndexOfScalar(u8, str, '.').?;
        const messageEnc, const signatureEnc = .{ str[0..sigSplit], str[sigSplit + 1 ..] };

        const header = try decodePart(arena.allocator(), HeaderRoot, messageEnc[0..std.mem.indexOfScalar(u8, messageEnc, '.').?]);
        const claims = try verify(arena.allocator(), header.alg, key, ClaimSet, messageEnc, signatureEnc, validation);

        return .{
            .arena = arena,
            .header = header,
            .claims = claims,
        };
    }
    return error.MalformedJWT;
}

pub fn verify(
    allocator: std.mem.Allocator,
    algo: Algorithm,
    key: DecodingKey,
    comptime ClaimSet: type,
    msg: []const u8,
    sigEnc: []const u8,
    validation: Validation,
) !ClaimSet {
    const decoder = std.base64.url_safe_no_pad.Decoder;
    const sig = try allocator.alloc(u8, try decoder.calcSizeForSlice(sigEnc));
    _ = try decoder.decode(sig, sigEnc);

    if (!validation.skip_secret) {
        switch (algo) {
            .HS256 => {
                var dest: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
                var src: [dest.len]u8 = undefined;
                std.crypto.auth.hmac.sha2.HmacSha256.create(&dest, msg, switch (key) {
                    .secret => |v| v,
                    else => return error.InvalidDecodingKey,
                });
                @memcpy(&src, sig);
                if (!std.crypto.utils.timingSafeEql([dest.len]u8, src, dest)) {
                    return error.InvalidSignature;
                }
            },
            .HS384 => {
                var dest: [std.crypto.auth.hmac.sha2.HmacSha384.mac_length]u8 = undefined;
                var src: [dest.len]u8 = undefined;
                std.crypto.auth.hmac.sha2.HmacSha384.create(&dest, msg, switch (key) {
                    .secret => |v| v,
                    else => return error.InvalidDecodingKey,
                });
                @memcpy(&src, sig);
                if (!std.crypto.utils.timingSafeEql([dest.len]u8, src, dest)) {
                    return error.InvalidSignature;
                }
            },
            .HS512 => {
                var dest: [std.crypto.auth.hmac.sha2.HmacSha512.mac_length]u8 = undefined;
                var src: [dest.len]u8 = undefined;
                std.crypto.auth.hmac.sha2.HmacSha512.create(&dest, msg, switch (key) {
                    .secret => |v| v,
                    else => return error.InvalidDecodingKey,
                });
                @memcpy(&src, sig);
                if (!std.crypto.utils.timingSafeEql([dest.len]u8, src, dest)) {
                    return error.InvalidSignature;
                }
            },
            .ES256 => {
                var src: [std.crypto.sign.ecdsa.EcdsaP256Sha256.Signature.encoded_length]u8 = undefined;
                @memcpy(&src, sig);
                std.crypto.sign.ecdsa.EcdsaP256Sha256.Signature.fromBytes(src).verify(msg, switch (key) {
                    .es256 => |v| v,
                    else => return error.InvalidDecodingKey,
                }) catch {
                    return error.InvalidSignature;
                };
            },
            .ES384 => {
                var src: [std.crypto.sign.ecdsa.EcdsaP384Sha384.Signature.encoded_length]u8 = undefined;
                @memcpy(&src, sig);
                std.crypto.sign.ecdsa.EcdsaP384Sha384.Signature.fromBytes(src).verify(msg, switch (key) {
                    .es384 => |v| v,
                    else => return error.InvalidDecodingKey,
                }) catch {
                    return error.InvalidSignature;
                };
            },
            // .PS256 => {
            //     const modulus_len = 256;
            //     const psSig = std.crypto.Certificate.rsa.PSSSignature.fromBytes(modulus_len, sig);
            //     std.crypto.Certificate.rsa.PSSSignature.verify(modulus_len, psSig, msg, switch (key) {
            //         .rsa => |v| v,
            //         else => return error.InvalidDecodingKey,
            //     }, std.crypto.hash.sha2.Sha256) catch {
            //         return error.InvalidSignature;
            //     };
            // },
            .EdDSA => {
                var src: [std.crypto.sign.Ed25519.Signature.encoded_length]u8 = undefined;
                @memcpy(&src, sig);
                std.crypto.sign.Ed25519.Signature.fromBytes(src).verify(msg, switch (key) {
                    .edsa => |v| v,
                    else => return error.InvalidDecodingKey,
                }) catch {
                    return error.InvalidSignature;
                };
            },

            //
            //
            else => return error.TODO,
        }
    }

    try validation.validate(
        try decodePart(allocator, Validation.RegisteredClaims, msg[std.mem.indexOfScalar(u8, msg, '.').? + 1 ..]),
    );

    const claims = try decodePart(
        allocator,
        ClaimSet,
        msg[std.mem.indexOfScalar(u8, msg, '.').? + 1 ..],
    );

    return claims;
}

/// Key used for encoding JWT token components
pub const EncodingKey = union(enum) {
    secret: []const u8,
    edsa: std.crypto.sign.Ed25519.SecretKey,
    es256: std.crypto.sign.ecdsa.EcdsaP256Sha256.SecretKey,
    es384: std.crypto.sign.ecdsa.EcdsaP384Sha384.SecretKey,

    /// create a new edsa encoding key from edsa secret key bytes
    pub fn fromEdsaBytes(bytes: [std.crypto.sign.Ed25519.SecretKey.encoded_length]u8) !@This() {
        return .{ .edsa = try std.crypto.sign.Ed25519.SecretKey.fromBytes(bytes) };
    }

    pub fn fromEs256Bytes(bytes: [std.crypto.ecdsa.EcdsaP256Sha256.SecretKey.encoded_length]u8) !@This() {
        return .{ .es256 = try std.crypto.sign.ecdsa.EcdsaP256Sha256.SecretKey.fromBytes(bytes) };
    }

    pub fn fromEs384Bytes(bytes: [std.crypto.ecdsa.EcdsaP384Sha384.SecretKey.encoded_length]u8) !@This() {
        return .{ .es384 = try std.crypto.sign.ecdsa.EcdsaP384Sha384.SecretKey.fromBytes(bytes) };
    }
};

fn encodePart(
    allocator: std.mem.Allocator,
    part: anytype,
) ![]const u8 {
    const encoder = std.base64.url_safe_no_pad.Encoder;
    const json = try std.json.stringifyAlloc(allocator, part, .{ .emit_null_optional_fields = false });
    defer allocator.free(json);
    const enc = try allocator.alloc(u8, encoder.calcSize(json.len));
    _ = encoder.encode(enc, json);
    return enc;
}

fn sign(
    allocator: std.mem.Allocator,
    msg: []const u8,
    algo: Algorithm,
    key: EncodingKey,
) ![]const u8 {
    return switch (algo) {
        .HS256 => blk: {
            var dest: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha256.create(&dest, msg, switch (key) {
                .secret => |v| v,
                else => return error.InvalidEncodingKey,
            });
            break :blk allocator.dupe(u8, &dest);
        },
        .HS384 => blk: {
            var dest: [std.crypto.auth.hmac.sha2.HmacSha384.mac_length]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha384.create(&dest, msg, switch (key) {
                .secret => |v| v,
                else => return error.InvalidEncodingKey,
            });
            break :blk allocator.dupe(u8, &dest);
        },
        .HS512 => blk: {
            var dest: [std.crypto.auth.hmac.sha2.HmacSha512.mac_length]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha512.create(&dest, msg, switch (key) {
                .secret => |v| v,
                else => return error.InvalidEncodingKey,
            });
            break :blk allocator.dupe(u8, &dest);
        },
        .ES256 => blk: {
            const pair = try std.crypto.sign.ecdsa.EcdsaP256Sha256.KeyPair.fromSecretKey(switch (key) {
                .es256 => |v| v,
                else => return error.InvalidEncodingKey,
            });
            const dest = (try pair.sign(msg, null)).toBytes();
            break :blk allocator.dupe(u8, &dest);
        },
        .ES384 => blk: {
            const pair = try std.crypto.sign.ecdsa.EcdsaP384Sha384.KeyPair.fromSecretKey(switch (key) {
                .es384 => |v| v,
                else => return error.InvalidEncodingKey,
            });
            const dest = (try pair.sign(msg, null)).toBytes();
            break :blk allocator.dupe(u8, &dest);
        },
        .EdDSA => blk: {
            const pair = try std.crypto.sign.Ed25519.KeyPair.fromSecretKey(switch (key) {
                .edsa => |v| v,
                else => return error.InvalidEncodingKey,
            });
            const dest = (try pair.sign(msg, null)).toBytes();
            break :blk allocator.dupe(u8, &dest);
        },
        else => return error.TODO,
    };
}

pub fn encode(
    allocator: std.mem.Allocator,
    header: HeaderRoot,
    claims: anytype,
    key: EncodingKey,
) ![]const u8 {
    comptime {
        if (@typeInfo(@TypeOf(claims)) != .@"struct") {
            @compileError("expected claims to be a struct but was a " ++ @typeName(@TypeOf(claims)));
        }
    }

    const encoder = std.base64.url_safe_no_pad.Encoder;

    const header_enc = try encodePart(allocator, header);
    defer allocator.free(header_enc);

    const claims_enc = try encodePart(allocator, claims);
    defer allocator.free(claims_enc);

    const msg = try std.mem.join(allocator, ".", &.{ header_enc, claims_enc });
    defer allocator.free(msg);

    const sig = try sign(allocator, msg, header.alg, key);
    defer allocator.free(sig);
    const sig_enc = try allocator.alloc(u8, encoder.calcSize(sig.len));
    defer allocator.free(sig_enc);
    _ = encoder.encode(sig_enc, sig);

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try buf.appendSlice(msg);
    try buf.append('.');
    try buf.appendSlice(sig_enc);

    return try buf.toOwnedSlice();
}

pub fn getHeader(header_str: []const u8, allocator: std.mem.Allocator) !Header {
    const header = try std.json.parseFromSlice(Header, allocator, header_str, .{});
    // defer header.deinit();
    return header.value;
}

pub fn getPayload(payload_str: []const u8, allocator: std.mem.Allocator) !Payload {
    const payload = try std.json.parseFromSlice(Payload, allocator, payload_str, .{});
    // defer payload.deinit();
    return payload.value;
}

pub const GoogleIdToken = struct {
    iss: []const u8,
    azp: []const u8,
    aud: []const u8,
    sub: []const u8,
    email: []const u8,
    email_verified: bool,
    at_hash: []const u8,
    iat: i64,
    exp: i64,
};
pub fn getRefreshPayload(payload_str: []const u8, allocator: std.mem.Allocator) !GoogleIdToken {
    const payload = try std.json.parseFromSlice(GoogleIdToken, allocator, payload_str, .{});
    // defer payload.deinit();
    return payload.value;
}

// Example usage
test "decode jwt" {
    const token = "eyJhbGciOiJSUzI1NiIsImtpZCI6IjYzMzdiZTYzNjRmMzgyNDAwOGQwZTkwMDNmNTBiYjZiNDNkNWE5YzYiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20iLCJhenAiOiI4NjgwNjE0MzYyNjAtNGlybWd2Z2hxbTgxMDdpMjFpb2RyODhyOHV1MTBnNXUuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJhdWQiOiI4NjgwNjE0MzYyNjAtNGlybWd2Z2hxbTgxMDdpMjFpb2RyODhyOHV1MTBnNXUuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdWIiOiIxMDg2NDQ4Nzg3MDcwNDM3NjI5NDgiLCJlbWFpbCI6InYucm9reC5uZWxsZW1hbm5AZ21haWwuY29tIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsImF0X2hhc2giOiIzOXZpYkVJM0NfV3FYMmtFcmZ0UTBRIiwibmFtZSI6IlZpYy1BdWd1c3QgUm9reC1OZWxsZW1hbm4iLCJwaWN0dXJlIjoiaHR0cHM6Ly9saDMuZ29vZ2xldXNlcmNvbnRlbnQuY29tL2EvQUNnOG9jSlJRZFhHOVd5UGNubDllZjdBSFhjUkZ0REFJLVNXWURGeXNySHNoZGtGaW9IeG45WT1zOTYtYyIsImdpdmVuX25hbWUiOiJWaWMtQXVndXN0IiwiZmFtaWx5X25hbWUiOiJSb2t4LU5lbGxlbWFubiIsImlhdCI6MTczNzQ5NjUwNywiZXhwIjoxNzM3NTAwMTA3fQ.SUiA-TxTAapA3BzEv68gBSUC0tZ_tatxcd-sHc9MA_A1n7XN1VRrW4kHmUA2o3vL9Fi3y6CjI9yaYKS6jhsYddesfKDwG_YGF1SKRNDMAF6ROs_ZIDnWVxzpu3wUl3MhOzDEPh2M1Wii0PnPVim5NaJFEhnuYSzJpRQI_2s_jMAs-QfTYXx0pG4vtJJaGYTloXwmsiKEXpT-F0fAPMBVFUaDLYM9SMy4ztrR2ZbupTIe1a7lG1T5nJlec5j3KdfQZWqV5wCZ_SNq79fzVbndB71sHfdwBoScqjJeFBGTrA_Y_GM2PIa2u-HduZviJ7Eki2n95IzUvYBj7GDZUfUDbg";
    const jwt = try decode(token);

    // Initialize an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse the header
    const header = try std.json.parseFromSlice(Header, allocator, jwt.header, .{});
    defer header.deinit();

    // Parse the payload
    const payload = try std.json.parseFromSlice(Payload, allocator, jwt.payload, .{});
    defer payload.deinit();

    // Print the parsed header
    std.debug.print("Header:\n", .{});
    std.debug.print("  alg: {s}\n", .{header.value.alg});
    std.debug.print("  kid: {s}\n", .{header.value.kid});
    std.debug.print("  typ: {s}\n", .{header.value.typ});

    // Print the parsed payload
    std.debug.print("\nPayload:\n", .{});
    std.debug.print("  iss: {s}\n", .{payload.value.iss});
    std.debug.print("  azp: {s}\n", .{payload.value.azp});
    std.debug.print("  aud: {s}\n", .{payload.value.aud});
    std.debug.print("  sub: {s}\n", .{payload.value.sub});
    std.debug.print("  email: {s}\n", .{payload.value.email});
    std.debug.print("  email_verified: {}\n", .{payload.value.email_verified});
    std.debug.print("  at_hash: {s}\n", .{payload.value.at_hash});
    std.debug.print("  name: {s}\n", .{payload.value.name});
    std.debug.print("  picture: {s}\n", .{payload.value.picture});
    std.debug.print("  given_name: {s}\n", .{payload.value.given_name});
    std.debug.print("  family_name: {s}\n", .{payload.value.family_name});
    std.debug.print("  iat: {}\n", .{payload.value.iat});
    std.debug.print("  exp: {}\n", .{payload.value.exp});
}
