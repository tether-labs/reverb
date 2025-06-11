const std = @import("std");
const Allocator = std.mem.Allocator;
// const DLinkedList = @import("storage/dll.zig").DLinkedList;

pub const RESP = union(enum) {
    const Self = @This();
    array: struct { values: []RESP, allocator: *Allocator },
    string: []const u8,
    json: []const u8,
    int: i32,
    // dll: *DLinkedList,
    float: f32,
    boolean: bool,
    map: *std.StringHashMap(RESP),

    pub fn toCommand(self: Self) !?Command {
        return switch (self) {
            .array => |v| {
                if (v.values.len == 1 and std.ascii.eqlIgnoreCase(v.values[0].string, "PING")) {
                    defer v.allocator.free(v.values[0].string);
                    return Command{ .ping = {} };
                }
                if (v.values.len == 2 and std.ascii.eqlIgnoreCase(v.values[0].string, "ECHO")) {
                    defer v.allocator.free(v.values[0].string);
                    return Command{ .echo = v.values[1].string };
                }
                if (std.ascii.eqlIgnoreCase(v.values[0].string, "SET")) {
                    defer v.allocator.free(v.values[0].string);
                    return Command{ .set = .{
                        .key = v.values[1].string,
                        .value = v.values[2],
                    } };
                }
                if (std.ascii.eqlIgnoreCase(v.values[0].string, "JSONSET")) {
                    defer v.allocator.free(v.values[0].string);
                    return Command{ .json_set = .{
                        .key = v.values[1].string,
                        .value = v.values[2],
                    } };
                }
                if (std.ascii.eqlIgnoreCase(v.values[0].string, "JSONGET")) {
                    defer v.allocator.free(v.values[0].string);
                    return Command{ .json_get = .{
                        .key = v.values[1].string,
                    } };
                }
                if (std.ascii.eqlIgnoreCase(v.values[0].string, "GET")) {
                    defer v.allocator.free(v.values[0].string);
                    return Command{ .get = .{
                        .key = v.values[1].string,
                    } };
                }
                if (std.ascii.eqlIgnoreCase(v.values[0].string, "DEL")) {
                    defer v.allocator.free(v.values[0].string);
                    return Command{ .del = .{
                        .key = v.values[1].string,
                    } };
                }
                if (std.ascii.eqlIgnoreCase(v.values[0].string, "LPUSH")) {
                    defer v.allocator.free(v.values[0].string);
                    return Command{ .lpush = .{
                        .dll_name = v.values[1].string,
                        .dll_new_value = v.values[2],
                    } };
                }
                if (std.ascii.eqlIgnoreCase(v.values[0].string, "LSET")) {
                    defer v.allocator.free(v.values[0].string);
                    const tag = std.meta.activeTag(v.values[2]);
                    const len = v.values.len;
                    const adj_len = v.values.len - 2;
                    const arr_str = try self.array.allocator.alloc(RESP, adj_len);

                    // We skip over the first 2 elements since it is the command and name of the list
                    for (2..len) |i| {
                        if (tag != std.meta.activeTag(v.values[i])) return error.AllValuesMustBeTheSameType;
                        arr_str[i - 2] = v.values[i];
                    }

                    return Command{ .lset = .{
                        .dll_name = v.values[1].string,
                        .dll_values = arr_str,
                        .tag = tag,
                    } };
                }
                if (std.ascii.eqlIgnoreCase(v.values[0].string, "LPUSHMANY")) {
                    defer v.allocator.free(v.values[0].string);
                    const tag = std.meta.activeTag(v.values[2]);
                    const len = v.values.len;
                    const adj_len = v.values.len - 2;
                    const arr_str = try self.array.allocator.alloc(RESP, adj_len);

                    // We skip over the first 2 elements since it is the command and name of the list
                    for (2..len) |i| {
                        if (tag != std.meta.activeTag(v.values[i])) return error.AllValuesMustBeTheSameType;
                        arr_str[i - 2] = v.values[i];
                    }

                    return Command{ .lpushmany = .{
                        .dll_name = v.values[1].string,
                        .dll_values = arr_str,
                        .tag = tag,
                    } };
                }
                if (std.ascii.eqlIgnoreCase(v.values[0].string, "HSET")) {
                    defer v.allocator.free(v.values[0].string);
                    const len = v.values.len;
                    const adj_len = v.values.len - 2;
                    const arr_resp = try self.array.allocator.alloc(RESP, adj_len);

                    for (2..len) |i| {
                        arr_resp[i - 2] = v.values[i];
                    }

                    return Command{ .hset = .{
                        .map_name = v.values[1].string,
                        .map_values = arr_resp,
                    } };
                }

                if (std.ascii.eqlIgnoreCase(v.values[0].string, "HGET")) {
                    defer v.allocator.free(v.values[0].string);
                    if (v.values[1] != .string) return error.InvalidArgumentType;
                    if (v.values[2] != .string) return error.InvalidArgumentType;
                    return Command{ .hget = .{
                        .map_name = v.values[1].string,
                        .key = v.values[2].string,
                    } };
                }

                if (std.ascii.eqlIgnoreCase(v.values[0].string, "LRANGE")) {
                    defer v.allocator.free(v.values[0].string);
                    if (v.values[2] != .int) return error.InvalidArgumentType;
                    if (v.values[3] != .int) return error.InvalidArgumentType;
                    return Command{ .lrange = .{
                        .dll_name = v.values[1].string,
                        .start_index = v.values[2].int,
                        .end_range = v.values[3].int,
                    } };
                }

                if (std.ascii.eqlIgnoreCase(v.values[0].string, "SETELEM")) {
                    defer v.allocator.free(v.values[0].string);
                    if (v.values[2] != .int) return error.InvalidArgumentType;
                    return Command{ .set_elem = .{
                        .dll_name = v.values[1].string,
                        .index = v.values[2].int,
                        .value = v.values[3],
                    } };
                }

                if (std.ascii.eqlIgnoreCase(v.values[0].string, "DELELEM")) {
                    defer v.allocator.free(v.values[0].string);
                    if (v.values[2] != .int) return error.InvalidArgumentType;
                    return Command{ .del_elem = .{
                        .dll_name = v.values[1].string,
                        .index = v.values[2].int,
                    } };
                }
                return null;
            },
            .string => |v| {
                if (std.ascii.eqlIgnoreCase(v, "PING")) {
                    return Command{ .ping = {} };
                }
                if (std.ascii.eqlIgnoreCase(v, "GETMETRICS")) {
                    return Command{ .metrics = {} };
                }
                if (std.ascii.eqlIgnoreCase(v, "GETALLKEYS")) {
                    return Command{ .get_all_keys = {} };
                }
                return null;
            },
            // .dll => {
            //     return null;
            // },
            .int => |_| {
                return null;
            },
            .float => |_| {
                return null;
            },
            .boolean => |_| {
                return null;
            },
            .map => |_| {
                return null;
            },
            .json => |_| {
                return null;
            },
        };
    }
};

pub const Command = union(enum) {
    echo: []const u8,
    ping: void,
    get: struct { key: []const u8 },
    set: struct { key: []const u8, value: RESP },
    json_set: struct { key: []const u8, value: RESP },
    json_get: struct { key: []const u8 },
    del: struct { key: []const u8 },
    get_all_keys: void,
    metrics: void,
    lpush: struct {
        dll_name: []const u8,
        dll_new_value: RESP,
    },
    lset: struct {
        dll_name: []const u8,
        dll_values: []RESP,
        tag: std.meta.Tag(RESP),
    },
    lpushmany: struct {
        dll_name: []const u8,
        dll_values: []RESP,
        tag: std.meta.Tag(RESP),
    },
    lrange: struct {
        dll_name: []const u8,
        start_index: i32,
        end_range: i32,
    },
    set_elem: struct {
        dll_name: []const u8,
        index: i32,
        value: RESP,
    },
    del_elem: struct {
        dll_name: []const u8,
        index: i32,
    },
    hget: struct {
        map_name: []const u8,
        key: []const u8,
    },
    hset: struct {
        map_name: []const u8,
        map_values: []RESP,
    },
};

pub const CommandError = error{
    CommandNotFound,
};

// test "multi command" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     var allocator = gpa.allocator();
//     var arr_set = [_]RESP{
//         RESP{ .string = "SET" },
//         RESP{ .string = "age" },
//         RESP{ .int = 12 },
//         RESP{ .string = "SET" },
//         RESP{ .string = "name" },
//         RESP{ .string = "Vic" },
//         RESP{ .string = "SET" },
//         RESP{ .string = "height" },
//         RESP{ .int = 175 },
//         RESP{ .string = "LPUSH" },
//         RESP{ .string = "DLLNAME" },
//         RESP{ .string = "DLLVALUE" },
//         RESP{ .string = "GET" },
//         RESP{ .string = "name" },
//         RESP{ .string = "LRANGE" },
//         RESP{ .string = "DLLNAME" },
//         RESP{ .int = 0 },
//         RESP{ .int = 1 },
//         RESP{ .string = "LPUSHMANY" },
//         RESP{ .string = "DLLNAME" },
//         RESP{ .string = "one" },
//         RESP{ .string = "two" },
//         RESP{ .string = "three" },
//         RESP{ .string = "four" },
//     };
//     const resp = RESP{ .array = .{ .values = &arr_set, .allocator = &allocator } };
//     var cmd_values = resp;
//     const len = resp.array.values.len;
//     var pos_command: u16 = 0;
//     switch (resp) {
//         .array => {
//             while (pos_command < len) {
//                 cmd_values.array.values = resp.array.values[pos_command..];
//                 const cmd = try cmd_values.toCommand();
//                 // std.debug.print("\narray: {any}\n", .{cmd_values});
//                 // std.debug.print("\nCommand: {any}\n", .{cmd.?});
//                 // std.debug.print("\npos: {d}\n", .{pos_command});
//                 switch (cmd.?) {
//                     .ping => {
//                         pos_command += 1;
//                     },
//                     .echo => {
//                         pos_command += 2;
//                     },
//                     .set => {
//                         pos_command += 3;
//                     },
//                     .json_set => {
//                         pos_command += 3;
//                     },
//                     .get => {
//                         pos_command += 2;
//                     },
//                     .json_get => {
//                         pos_command += 2;
//                     },
//                     .get_all_keys => {
//                         pos_command += 1;
//                     },
//                     .metrics => {
//                         pos_command += 1;
//                     },
//                     .del => {
//                         pos_command += 2;
//                     },
//                     .del_elem => {
//                         pos_command += 2;
//                     },
//                     .set_elem => {
//                         pos_command += 3;
//                     },
//
//                     .lpush => {
//                         pos_command += 3;
//                     },
//                     .lset => |v| {
//                         pos_command += 2;
//                         const len_v: u16 = @intCast(v.dll_values.len);
//                         pos_command += len_v;
//                     },
//                     .lpushmany => |v| {
//                         pos_command += 2;
//                         const len_v: u16 = @intCast(v.dll_values.len);
//                         pos_command += len_v;
//                     },
//                     .lrange => {
//                         pos_command += 4;
//                     },
//                     .hset => |v| {
//                         const num_values: u16 = @intCast(v.map_values.len);
//                         pos_command += num_values + 2;
//                     },
//                     .hget => {
//                         pos_command += 3;
//                     },
//                 }
//             }
//         },
//         else => {},
//     }
// }
//
// test "test to Command" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     var allocator = gpa.allocator();
//
//     var arr_set = [_]RESP{
//         RESP{ .string = "SET" },
//         RESP{ .string = "name" },
//         RESP{ .string = "Vic" },
//     };
//     var resp = RESP{ .array = .{ .values = &arr_set, .allocator = &allocator } };
//
//     var cmd = resp.toCommand();
//     var command = Command{ .set = .{
//         .key = "name",
//         .value = RESP{ .string = "Vic" },
//     } };
//     try std.testing.expectEqualDeep(command, cmd);
//
//     var arr_get = [_]RESP{
//         RESP{ .string = "GET" },
//         RESP{ .string = "name" },
//     };
//
//     resp = RESP{ .array = .{ .values = &arr_get, .allocator = &allocator } };
//
//     cmd = resp.toCommand();
//     command = Command{ .get = .{
//         .key = "name",
//     } };
//     try std.testing.expectEqualDeep(command, cmd);
// }
