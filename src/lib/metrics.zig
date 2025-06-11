const std = @import("std");
const print = std.debug.print;
const Tether = @import("server.zig");
const Radix = @import("trees/radix.zig");
const Context = @import("context.zig");

pub const Metrics = @This();
tether: *Tether,

pub const EndPoints = struct {
    POST: ?[][]const u8 = &[_][]const u8{},
    GET: ?[][]const u8 = &[_][]const u8{},
    PATCH: ?[][]const u8 = &[_][]const u8{},
    DELETE: ?[][]const u8 = &[_][]const u8{},
    UPDATE: ?[][]const u8 = &[_][]const u8{},
};

pub var end_points = EndPoints{};

const Methods = enum {
    GET,
    POST,
    PATCH,
    DELETE,
    UPDATE,
};

const methods = [5][]const u8{
    "GET",
    "POST",
    "PATCH",
    "DELETE",
    "UPDATE",
};

pub fn init(target: *Metrics, tether: *Tether) void {
    target.* = .{
        .tether = tether,
    };
}

fn allocateRoute(
    node: Radix.Node,
    buffer: *std.ArrayList(u8),
    all_routes: *std.ArrayList([]const u8),
    allocator: *std.mem.Allocator,
) !void {
    // Save current buffer length to backtrack later
    const original_len = buffer.items.len;

    // Append this node's prefix to the buffer
    if (node.prefix.len > 0) {
        try buffer.appendSlice(node.prefix);
    }

    // print("\n{s}", .{node.prefix});
    // If this node marks the end of a word, print the accumulated buffer
    if (node.is_end) {
        try buffer.append('/');
        print("{s}\n", .{buffer.items});
        const route = try std.fmt.allocPrint(allocator.*, "{s}", .{buffer.items});
        try all_routes.append(route);
    }

    // Recursively process all children
    var children_itr = node.children.iterator();
    while (children_itr.next()) |child| {
        try allocateRoute(child.value_ptr.*.*, buffer, all_routes, allocator);
    }

    if (node.param_child) |child| {
        if (child.is_end) {
            try buffer.appendSlice(child.prefix);
            print("{s}\n", .{buffer.items});
        }
    }

    // Backtrack: remove this node's prefix to prepare for sibling paths
    buffer.shrinkRetainingCapacity(original_len);
}

// This maps all teh routes the system hhas
pub fn mapRoutes(metrics: *Metrics) !void {
    const radix_itr = metrics.tether.routes;
    for (radix_itr, 0..) |route, idx| {
        var all_routes = std.ArrayList([]const u8).init(metrics.tether.arena.*);
        const node = route.root.*;
        var buffer = std.ArrayList(u8).init(metrics.tether.arena.*);
        try allocateRoute(node, &buffer, &all_routes, metrics.tether.arena);
        const method_str = methods[idx];
        const method = std.meta.stringToEnum(Methods, method_str) orelse return error.Null;
        switch (method) {
            .GET => end_points.GET = try all_routes.toOwnedSlice(),
            .POST => end_points.POST = try all_routes.toOwnedSlice(),
            .DELETE => end_points.DELETE = try all_routes.toOwnedSlice(),
            .PATCH => end_points.PATCH = try all_routes.toOwnedSlice(),
            .UPDATE => end_points.UPDATE = try all_routes.toOwnedSlice(),
        }
    }
}

pub fn getAllRoutes(ctx: *Context) !void {
    try ctx.JSON(EndPoints, end_points);
}

pub fn healthCheck(ctx: *Context) !void {
    try ctx.STRING("Success");
}
