//     e - l - l - o
//   /
// h - a - t
//       \
//        v - e
const std = @import("std");
const print = std.debug.print;
const mem = std.mem;
const Context = @import("../context.zig");
const Ctx_pm = @import("../handler.zig").Ctx_pm;

const HandlerFunc = *const fn (*Context) anyerror!void;
const MiddleFunc = *const fn (HandlerFunc, *Context) anyerror!HandlerFunc;

// const HandlerFunc = *const fn ([]const u8) void;
// const MiddleFunc = *const fn (HandlerFunc, []const u8) HandlerFunc;

const RadixError = error{
    FailedToInitRadix,
    FailedToCreateNode,
};

const RouteFunc = struct {
    handler_func: HandlerFunc,
    middlewares: []const MiddleFunc,
};

const ParamInfo = struct { param: []const u8, value: []const u8 };
const RouteHandler = struct {
    route_func: ?RouteFunc,
    param_args: ?*std.ArrayList(ParamInfo) = null,
};

const Radix = @This();
allocator: std.mem.Allocator,
root: *Node,

fn findCommonPrefix(a: []const u8, b: []const u8) usize {
    var i: usize = 0;
    while (i < a.len and i < b.len and a[i] == b[i]) : (i += 1) {}
    return i;
}

pub const Node = struct {
    prefix: []const u8,
    value: ?RouteFunc,
    query_param: []const u8,
    is_dynamic: bool,
    children: std.AutoHashMap(u8, *Node),
    param_child: ?*Node,
    is_end: bool,

    fn findChildWithCommonPrefix(node: *Node, prefix: []const u8) ?*Node {
        var children_itr = node.children.iterator();
        var best_match: ?*Node = null;
        var max_common_len: usize = 0;

        while (children_itr.next()) |c| {
            const child_prefix = c.value_ptr.*.prefix;
            const common_len = findCommonPrefix(child_prefix, prefix);
            if (common_len > max_common_len) {
                max_common_len = common_len;
                best_match = c.value_ptr.*;
            }
        }
        return best_match;
    }

    // Adjust splitNode to handle new child structure
    fn splitNode(
        self: *Node,
        at: usize,
        allocator: std.mem.Allocator,
    ) !*Node {
        const new_node = try allocator.create(Node);
        new_node.* = Node{
            .prefix = self.prefix[at..],
            .value = self.value,
            .query_param = self.query_param,
            .is_dynamic = self.is_dynamic,
            .children = self.children,
            .param_child = self.param_child,
            .is_end = true,
        };

        self.prefix = self.prefix[0..at];
        self.children = std.AutoHashMap(u8, *Node).init(allocator);
        // Insert new node using first character of its prefix
        try self.children.put(new_node.prefix[0], new_node);
        self.is_end = false;

        return new_node;
    }

    // // hello is the node and i is 4 since we passed hell
    // fn splitNode(
    //     self: *Node,
    //     at: usize,
    //     allocator: std.mem.Allocator,
    // ) !*Node {
    //     // We take the current node and set it as the child,
    //     // so now we move everything from current to child
    //     // current = handleUsers -> child = handleUsers while now current = handlerUser
    //     // since we split the node
    //     // we create a new node of o
    //     const new_node = try allocator.create(Node);
    //     new_node.* = Node{
    //         .prefix = self.prefix[at..],
    //         .value = self.value,
    //         .query_param = self.query_param,
    //         .is_dynamic = self.is_end,
    //         .children = self.children,
    //         .param_child = self.param_child,
    //         .is_end = true,
    //     };
    //
    //     // set the current node to hell
    //     self.prefix = self.prefix[0..at];
    //     self.children = std.StringHashMap(*Node).init(allocator);
    //     // store the new_node o in the hell node
    //     try self.children.put(new_node.prefix, new_node);
    //
    //     return new_node;
    // }
};

pub fn init(target: *Radix, arena: *std.mem.Allocator) !void {
    const root_node = try arena.create(Node);
    root_node.* = Node{
        .prefix = "",
        .value = null,
        .query_param = "",
        .is_dynamic = false,
        .children = std.AutoHashMap(u8, *Node).init(arena.*),
        .param_child = null,
        .is_end = false,
    };
    target.* = .{
        .root = root_node,
        .allocator = arena.*,
    };
}
fn newNode(
    radix: *Radix,
    prefix: []const u8,
    value: ?RouteFunc,
    query_param: []const u8,
    is_end: bool,
) !*Node {
    const node = try radix.allocator.create(Node);
    node.* = Node{
        .prefix = prefix, // Initialize the prefix field
        .value = value,
        .query_param = query_param,
        .is_dynamic = false,
        .children = std.AutoHashMap(u8, *Node).init(radix.allocator),
        .param_child = null,
        .is_end = is_end,
    };
    return node;
}

fn findSegmentEndIdx(path: []const u8) usize {
    var idx: usize = 0;
    while (idx < path.len and path[idx] != '/') : (idx += 1) {
        if (path[idx] == 0) return idx;
    }
    return idx;
}

// /api/test
pub fn searchRoute(radix: *const Radix, path: []const u8) !?RouteHandler {
    // var param_args: ?*std.ArrayList(ParamInfo) = null;
    var node = radix.root;
    var start: usize = 1;

    // Manually parse path segments to avoid iterator overhead
    while (start < path.len) : (start += 1) {
        if (path[start] == '/') continue;
        if (path[start] == ' ') break;
        if (path[start] == 0) break;
        // api/test
        // Skip leading slashes
        if (start >= path.len) break;
        const end = findSegmentEndIdx(path[start..]) + start;
        const segment = path[start..end];
        start = end;

        var remaining = segment;
        while (remaining.len > 0) {
            // const match = node.findChildWithCommonPrefix(remaining) orelse break;
            const first_char = remaining[0];
            const match = node.children.get(first_char) orelse break;
            const common_len = findCommonPrefix(match.prefix, remaining);

            if (common_len != match.prefix.len) return null;
            remaining = remaining[common_len..];
            node = match;
        }

        // Handle dynamic parameters
        if (node.param_child) |dynamic_child| {
            // Look ahead for next segment
            var param_start = start;
            while (param_start < path.len and path[param_start] == '/') : (param_start += 1) {}
            if (param_start >= path.len) break;

            const param_end = std.mem.indexOfScalarPos(u8, path, param_start, '/') orelse path.len;
            _ = path[param_start..param_end];
            start = param_end + 1;

            // Lazy initialization of param_args
            // if (param_args == null) {
            //     param_args = try radix.allocator.create(std.ArrayList(ParamInfo));
            //     param_args.?.* = try std.ArrayList(ParamInfo).initCapacity(radix.allocator, 2);
            // }

            // try param_args.?.append(.{
            //     .param = dynamic_child.query_param,
            //     .value = param_value,
            // });
            node = dynamic_child;
        }
    }

    if (node.is_end) {
        // if (param_args == null) {
        // var args = std.ArrayList(ParamInfo).init(radix.allocator);
        //     return RouteHandler{
        //         .route_func = node.value,
        //         // .param_args = &args,
        //     };
        // }
        return RouteHandler{
            .route_func = node.value,
            // .param_args = param_args.?,
        };
    }
    return null;
}

pub fn addRoute(
    radix: *Radix,
    path: []const u8,
    handler: HandlerFunc,
    middlewares: []const MiddleFunc,
) !void {
    var path_iter = mem.tokenizeScalar(u8, path, '/');
    try radix.insert(&path_iter, handler, middlewares);
}

fn insert(
    radix: *Radix,
    segments: *mem.TokenIterator(u8, .scalar),
    handler: HandlerFunc,
    middlewares: []const MiddleFunc,
) !void {
    var node = radix.root;
    const route_func = RouteFunc{
        .handler_func = handler,
        .middlewares = middlewares,
    };
    while (segments.next()) |segment| {
        var segement_remaining = segment;
        const is_dynamic = segment[0] == ':';
        if (is_dynamic) {
            const param = segment[1..];

            if (node.param_child) |_| return error.ConflictDynamicRoute;
            // check the current node hello startwith hell
            const dynamic_node = try radix.newNode(":dynamic", route_func, param, true);
            node.param_child = dynamic_node;
            return;
        }

        // Inside the insertion loop:
        while (segement_remaining.len > 0) {
            // hell is common with hello, hell
            // this finds is there is a child with hell prefix
            const matching_child = node.findChildWithCommonPrefix(segement_remaining);
            if (matching_child) |child| {
                var i: usize = 0;
                // The word_remingin is hello
                // Find length of common prefix which is hell for hello which is 4
                while (i < child.prefix.len and i < segement_remaining.len and child.prefix[i] == segement_remaining[i]) : (i += 1) {}

                if (i < child.prefix.len) {
                    _ = try child.splitNode(i, radix.allocator);
                    // Once we splitt the node we need to set the current to the correct route func
                    child.value = route_func;
                    child.prefix = segement_remaining[0..i];
                    child.param_child = null;
                    node = child;
                    // Focus on the PARENT (the split node, now "hell")
                } else {
                    node = child;
                }
                // Advance the word remianing
                segement_remaining = segement_remaining[i..];
            } else {
                // const param = if (is_dynamic) segment[1..] else "";
                // create a new RouteFunc
                // check the current node hello startwith hell
                const new_node = try radix.newNode(
                    segement_remaining,
                    route_func,
                    "",
                    false,
                );
                try node.children.put(segement_remaining[0], new_node);
                node = new_node;
                break;
            }
        }
    }
    node.is_end = true;
}

fn printTree(radix: *const Radix) !void {
    var buffer = std.ArrayList(u8).init(radix.allocator);
    defer buffer.deinit();
    // Start traversal from the root's children (root itself has no prefix)
    try printNode(radix.root, &buffer);
}

fn printNode(node: *const Node, buffer: *std.ArrayList(u8)) !void {
    // Save current buffer length to backtrack later
    const original_len = buffer.items.len;

    // Append this node's prefix to the buffer
    try buffer.appendSlice(node.prefix);

    // print("\n{s}", .{node.prefix});
    // If this node marks the end of a word, print the accumulated buffer
    if (node.is_end) {
        print("{s}\n", .{buffer.items});
    }

    // Recursively process all children
    var children_itr = node.children.iterator();
    while (children_itr.next()) |child| {
        try printNode(child.value_ptr.*, buffer);
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

fn handlePosts(path: []const u8) void {
    std.debug.print("\nPost request: {s} \n", .{path});
}
fn handlePostsDynamic(path: []const u8) void {
    std.debug.print("\nDynamic route: {s} \n", .{path});
}

fn handleUsers(path: []const u8) void {
    std.debug.print("\nUsers: {s} \n", .{path});
}
fn handleUser(path: []const u8) void {
    std.debug.print("\nUser: {s} \n", .{path});
}

fn handleIds(path: []const u8) void {
    std.debug.print("\nIds: {s} \n", .{path});
}

test "radix tree insert" {
    var radix: Radix = undefined;
    var allocator = std.heap.page_allocator;
    try radix.init(&allocator);
    // hell has children o and scape
    // try radix.addRoute("/users/posts/:name", handlePostsByName, &[_]MiddleFunc{});
    // try radix.addRoute("/users/posts/:id", handlePostsByName, &[_]MiddleFunc{});
    // Check if the order of dynamic and static matter !!!!!!!
    try radix.addRoute("/users", handleUsers, &[_]MiddleFunc{});
    try radix.addRoute("/users/:id", handlePostsDynamic, &[_]MiddleFunc{});
    try radix.addRoute("/user", handleUser, &[_]MiddleFunc{});
    // try radix.addRoute("/ap", handlePostsDynamic, &[_]MiddleFunc{});
    // try radix.addRoute("/apple", handlePosts, &[_]MiddleFunc{});
    // try radix.addRoute("/app/users", handleUsers, &[_]MiddleFunc{});
    // try radix.addRoute("/users/posts/:ids", handlePostsDynamic, &[_]MiddleFunc{});
    // try radix.addRoute("/users/posts", handlePostsDynamic, &[_]MiddleFunc{});
    const route = try radix.searchRoute("/users");
    if (route) |r| {
        r.route_func.?.handler_func("DDD");
        // print("\n{s}", .{r.param_args.*.items[0].value});
    }
    // try radix.printTree();
    // print("\n", .{});
    // try radix.insert("hat");
    // try radix.insert("have");
}
