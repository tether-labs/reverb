const std = @import("std");

pub const String = struct {
    start: usize,
    len: usize,
    capacity: usize,
    contents: [*]u8,

    pub fn new() String {
        return String{
            .start = 0,
            .len = 0,
            .capacity = 0,
            .contents = undefined,
        };
    }

    pub fn init(initial: []const u8) String {
        var new_string = String.new();
        new_string.append_str(initial);
        return new_string;
    }

    pub fn append_str(self: *String, input: []const u8) void {
        const required_len = self.len + input.len;
        const required_capacity = required_len + (10 - required_len % 10);

        // Case 1: contents exists and is big enough
        if (required_capacity <= self.capacity) {
            @memcpy(self.contents[self.len .. self.len + input.len], input);
            self.len = required_len;
            self.capacity = required_capacity;
        } else { // Case 2: contents not big enough
            const new_c: [*]u8 = @ptrCast(@alignCast(std.c.realloc(
                self.contents,
                required_capacity,
            )));
            self.contents = new_c;
            @memcpy(self.contents[self.len .. self.len + input.len], input);
            self.len = required_len;
            self.capacity = required_capacity;
        }
    }
};
