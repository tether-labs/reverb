const std = @import("std");
const testing = std.testing;
const dom = @import("dom.zig");
const allr = std.heap.page_allocator;
test "get with struct" {
    const Entertainment = struct {
        movies: []const u8,
    };

    const Pref = struct {
        notifications: bool,
        theme: []const u8,
        location: []const u8,
        entertainment: Entertainment,
        music: [][]const u8,
    };
    const ComplexData = struct {
        username: []const u8,
        email: []const u8,
        preferences: Pref,
        age: i32,
        // healthy: bool,
    };

    // const input =
    //     \\{"a": 42, "b": "b-string", "c": {"d": 126}}
    // ;

    const input =
        \\{
        \\    "username": "johndoe",
        \\    "email": "john@example.com",
        \\    "preferences": {
        \\        "theme": "dark",
        \\        "location": "Hell",
        \\        "music": [
        \\            "Metallica",
        \\            "John Mayer"
        \\        ],
        \\        "entertainment": {
        \\            "movies": "The Brutalist"
        \\        },
        \\        "notifications": true
        \\    },
        \\    "age": 26
        \\}
    ;

    // const parsed = try std.json.parseFromSlice(
    //     ComplexData,
    //     allr,
    //     input,
    //     .{},
    // );
    // _ = parsed.value;
    var parser = try dom.Parser.initFixedBuffer(allr, input, .{});
    defer parser.deinit();
    const start = std.time.nanoTimestamp();
    for (0..10) |_| {
        try dom.Parser.initExisting(&parser, input, .{});
        try parser.parse();
        var s: ComplexData = undefined;
        try parser.element().get_alloc(allr, &s);
    }
    const end = std.time.nanoTimestamp();
    std.debug.print("Elapsed Time: {any}ms\n", .{@divTrunc((end - start), 1000)});
    // try testing.expectEqualStrings("johndoe", s.username);
    // try testing.expectEqualStrings("john@example.com", s.email);
    // try testing.expectEqualStrings("Metallica", s.preferences.music[0]);
}

test "at_pointer" {
    const input =
        \\{"a": {"b": [1,2,3]}}
    ;
    var parser = try dom.Parser.initFixedBuffer(allr, input, .{});
    defer parser.deinit();
    try parser.parse();
    const b0 = try parser.element().at_pointer("/a/b/0");
    try testing.expectEqual(@as(i64, 1), try b0.get_int64());
}
