const std = @import("std");
const Allocator = std.mem.Allocator;
const Tripwire = @import("Tripwire.zig");
const TrackingAllocator = @import("TrackingAllocator.zig");
const posix = std.posix;
const system = std.posix.system;
const print = std.debug.print;
const log = std.log.scoped(.tcp_demo);
const Logger = @import("Logger.zig");
const Parsed = std.json.Parsed;
const net = std.net;
const Loom = @import("engine/Loom.zig");
const Scheduler = @import("engine/async/Scheduler.zig");
const Radix = @import("trees/radix.zig");
const Cors = @import("core/Cors.zig");
const Context = @import("context.zig");
const Metrics = @import("metrics.zig");
const Buckets = @import("metrics/Buckets.zig");
const getAllRoutes = Metrics.getAllRoutes;
const healthCheck = Metrics.healthCheck;
const EndPoints = Metrics.EndPoints;
const process = @import("handler.zig").handle;
const Ctx_pm = @import("handler.zig").Ctx_pm;
const StringBuilder = @import("core/builders.zig").String;
const ContentType = @import("helpers.zig").ContentType;

pub const Reverb = @This();
pub const Config = Loom.Config;
pub var instance: *Reverb = undefined;
var use_cors: bool = false;
// Radix tree
routes: [5]Radix,
arena: *Allocator,
config: Loom.Config,
tracking_allocator: ?*TrackingAllocator,
// cors: ?Cors = null,
logger: Logger,
// Event Loop
loom: Loom,
tripwire: Tripwire = undefined,
const HandlerFunc = *const fn (*Context) anyerror!void;
pub const Next = *const fn (*Context) anyerror!void;
pub const MiddleFunc = *const fn (Next, *Context) anyerror!HandlerFunc;
pub const GroupRoute = struct {
    path: []const u8,
    method: Methods,
    handler: HandlerFunc,
    middlewares: []const MiddleFunc,
};

const MethodLookup = struct {
    // First level lookup based on the first character of the method.
    first_char: [256]u8,

    /// Initializes a lookup table with predefined values for known HTTP methods.
    pub fn init() @This() {
        var table = @This(){
            // Create an array of 256 bytes, all initialized to 0.
            .first_char = [_]u8{0} ** 256,
        };

        // Assign a unique integer for each known HTTP method based on its first letter.
        // Note: If multiple methods share the same first letter (e.g. POST and PATCH),
        // they will both map to the same value.
        table.first_char['G'] = 0; // GET
        table.first_char['P'] = 1; // POST (or PATCH)
        table.first_char['D'] = 2; // DELETE
        table.first_char['H'] = 3; // HEAD
        table.first_char['O'] = 4; // OPTIONS
        table.first_char['C'] = 5; // CONNECT
        table.first_char['T'] = 6; // TRACE

        return table;
    }

    /// Returns the associated integer for a given HTTP method.
    /// If the method is empty or unknown, returns 0 (the default value).
    pub fn lookup(self: *const MethodLookup, method: []const u8) u8 {
        if (method.len == 0) return 0;
        return self.first_char[method[0]];
    }
}.init();

fn parseMiddleWare(func_num: usize, my_Handler: HandlerFunc, middleswares: []const MiddleFunc, ctx: *Context) !void {
    if (func_num + 1 > middleswares.len) {
        my_Handler(ctx) catch |err| {
            log.debug("Handler error: {any}", .{err});
            return err;
        };
    } else {
        const first_func = middleswares[func_num];
        const wrappedFunc = first_func(my_Handler, ctx) catch |err| {
            return err;
        };
        try parseMiddleWare(func_num + 1, wrappedFunc, middleswares, ctx);
    }
}

const Methods = enum {
    GET,
    POST,
    DELETE,
    HEAD,
    OPTIONS,
    CONNECT,
    TRACE,
};

/// This function adds the route to the reverb radix tree.
/// Deinitializes the reverb instance recursively calls routes deinit routes from radix tree
/// # Parameters:
/// - `target`: *Reverb.
/// - `path`: []const u8
/// - `method`: Methods,
/// - `handler`: HandlerFunc
/// - `middlewares`: []const MiddleFunc
///
/// # Returns:
/// !void.
pub fn addRoute(
    reverb: *Reverb,
    path: []const u8,
    method: Methods,
    handler: HandlerFunc,
    middlewares: []const MiddleFunc,
) !void {
    // const idx = MethodLookup.first_char[method[0]];
    var radix = reverb.routes[@as(usize, @intFromEnum(method))];
    const out = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{path});
    try radix.addRoute(out, handler, middlewares);
    const end_colon_op = std.mem.indexOf(u8, path, "/:");
    var route_path: []const u8 = path;
    if (end_colon_op) |end_colon| {
        route_path = path[0..end_colon];
    }
    // Add the path to the appropriate endpoints array
    switch (method) {
        .GET => try addToEndpoints(&Metrics.end_points.GET, route_path, reverb.arena.*),
        .POST => try addToEndpoints(&Metrics.end_points.POST, route_path, reverb.arena.*),
        .DELETE => try addToEndpoints(&Metrics.end_points.DELETE, route_path, reverb.arena.*),
        else => return error.CouldNotMatchMethod,
    }
    return;
}

/// This function adds the route to the reverb Get radix tree.
/// Deinitializes the reverb instance recursively calls routes deinit routes from radix tree
/// # Parameters:
/// - `target`: *Reverb.
/// - `path`: []const u8
/// - `handler`: HandlerFunc
/// - `middlewares`: []const MiddleFunc
///
/// # Returns:
/// !void.
pub fn get(
    reverb: *Reverb,
    path: []const u8,
    handler: HandlerFunc,
    middlewares: []const MiddleFunc,
) !void {
    var radix = reverb.routes[@as(usize, @intFromEnum(Methods.GET))];
    const out = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{path});
    try radix.addRoute(out, handler, middlewares);
    const end_colon_op = std.mem.indexOf(u8, path, "/:");
    var route_path: []const u8 = path;
    if (end_colon_op) |end_colon| {
        route_path = path[0..end_colon];
    }
    // Add the path to the appropriate endpoints array
    try addToEndpoints(&Metrics.end_points.GET, route_path, reverb.arena.*);
    return;
}

/// This function adds the route to the reverb Delete radix tree.
/// Deinitializes the reverb instance recursively calls routes deinit routes from radix tree
/// # Parameters:
/// - `target`: *Reverb.
/// - `path`: []const u8
/// - `handler`: HandlerFunc
/// - `middlewares`: []const MiddleFunc
///
/// # Returns:
/// !void.
pub fn post(
    reverb: *Reverb,
    path: []const u8,
    handler: HandlerFunc,
    middlewares: []const MiddleFunc,
) !void {
    var radix = reverb.routes[@as(usize, @intFromEnum(Methods.DELETE))];
    const out = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{path});
    try radix.addRoute(out, handler, middlewares);
    const end_colon_op = std.mem.indexOf(u8, path, "/:");
    var route_path: []const u8 = path;
    if (end_colon_op) |end_colon| {
        route_path = path[0..end_colon];
    }
    // Add the path to the appropriate endpoints array
    try addToEndpoints(&Metrics.end_points.DELETE, route_path, reverb.arena.*);
    return;
}

/// This function adds the route to the reverb Head radix tree.
/// Deinitializes the reverb instance recursively calls routes deinit routes from radix tree
/// # Parameters:
/// - `target`: *Reverb.
/// - `path`: []const u8
/// - `handler`: HandlerFunc
/// - `middlewares`: []const MiddleFunc
///
/// # Returns:
/// !void.
pub fn head(
    reverb: *Reverb,
    path: []const u8,
    handler: HandlerFunc,
    middlewares: []const MiddleFunc,
) !void {
    var radix = reverb.routes[@as(usize, @intFromEnum(Methods.HEAD))];
    const out = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{path});
    try radix.addRoute(out, handler, middlewares);
    const end_colon_op = std.mem.indexOf(u8, path, "/:");
    var route_path: []const u8 = path;
    if (end_colon_op) |end_colon| {
        route_path = path[0..end_colon];
    }
    // Add the path to the appropriate endpoints array
    try addToEndpoints(&Metrics.end_points.HEAD, route_path, reverb.arena.*);
    return;
}

/// This function adds the route to the reverb Options radix tree.
/// Deinitializes the reverb instance recursively calls routes deinit routes from radix tree
/// # Parameters:
/// - `target`: *Reverb.
/// - `path`: []const u8
/// - `handler`: HandlerFunc
/// - `middlewares`: []const MiddleFunc
///
/// # Returns:
/// !void.
pub fn options(
    reverb: *Reverb,
    path: []const u8,
    handler: HandlerFunc,
    middlewares: []const MiddleFunc,
) !void {
    var radix = reverb.routes[@as(usize, @intFromEnum(Methods.OPTIONS))];
    const out = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{path});
    try radix.addRoute(out, handler, middlewares);
    const end_colon_op = std.mem.indexOf(u8, path, "/:");
    var route_path: []const u8 = path;
    if (end_colon_op) |end_colon| {
        route_path = path[0..end_colon];
    }
    // Add the path to the appropriate endpoints array
    try addToEndpoints(&Metrics.end_points.OPTIONS, route_path, reverb.arena.*);
    return;
}

/// This function adds the route to the reverb Connect radix tree.
/// Deinitializes the reverb instance recursively calls routes deinit routes from radix tree
/// # Parameters:
/// - `target`: *Reverb.
/// - `path`: []const u8
/// - `handler`: HandlerFunc
/// - `middlewares`: []const MiddleFunc
///
/// # Returns:
/// !void.
pub fn connect(
    reverb: *Reverb,
    path: []const u8,
    handler: HandlerFunc,
    middlewares: []const MiddleFunc,
) !void {
    var radix = reverb.routes[@as(usize, @intFromEnum(Methods.CONNECT))];
    const out = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{path});
    try radix.addRoute(out, handler, middlewares);
    const end_colon_op = std.mem.indexOf(u8, path, "/:");
    var route_path: []const u8 = path;
    if (end_colon_op) |end_colon| {
        route_path = path[0..end_colon];
    }
    // Add the path to the appropriate endpoints array
    try addToEndpoints(&Metrics.end_points.CONNECT, route_path, reverb.arena.*);
    return;
}

/// This function adds the route to the reverb Trace radix tree.
/// Deinitializes the reverb instance recursively calls routes deinit routes from radix tree
/// # Parameters:
/// - `target`: *Reverb.
/// - `path`: []const u8
/// - `handler`: HandlerFunc
/// - `middlewares`: []const MiddleFunc
///
/// # Returns:
/// !void.
pub fn trace(
    reverb: *Reverb,
    path: []const u8,
    handler: HandlerFunc,
    middlewares: []const MiddleFunc,
) !void {
    var radix = reverb.routes[@as(usize, @intFromEnum(Methods.TRACE))];
    const out = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{path});
    try radix.addRoute(out, handler, middlewares);
    const end_colon_op = std.mem.indexOf(u8, path, "/:");
    var route_path: []const u8 = path;
    if (end_colon_op) |end_colon| {
        route_path = path[0..end_colon];
    }
    // Add the path to the appropriate endpoints array
    try addToEndpoints(&Metrics.end_points.TRACE, route_path, reverb.arena.*);
    return;
}

/// Helper function to add a path to the respective endpoints array
fn addToEndpoints(endpoints: *?[][]const u8, path: []const u8, allocator: std.mem.Allocator) !void {
    if (endpoints.*) |existing| {
        // Resize the existing array to accommodate one more path
        var new_endpoints = try allocator.realloc(existing, existing.len + 1);
        // Duplicate the path string to ensure it's owned by the endpoints
        new_endpoints[existing.len] = try allocator.dupe(u8, path);
        endpoints.* = new_endpoints;
    } else {
        // Create a new array with one path
        var new_endpoints = try allocator.alloc([]const u8, 1);
        new_endpoints[0] = try allocator.dupe(u8, path);
        endpoints.* = new_endpoints;
    }
}

pub fn groupRoutes(
    reverb: *Reverb,
    group_path: []const u8,
    grouped_routes: []const GroupRoute,
) !void {
    // pick a sane upper bound for your paths:
    // const MaxPathLen = 256;
    // var buf: [MaxPathLen]u8 = undefined;

    for (grouped_routes) |gr| {
        const out = try std.fmt.allocPrint(reverb.arena.*, "{s}{s}", .{ group_path, gr.path });
        try reverb.addRoute(out, gr.method, gr.handler, gr.middlewares);
    }
}

// Radix is a Radix tree routes is a hashmap with the method, each method has a radix tree
pub fn callRoute(reverb: *Reverb, ctx_pm: Ctx_pm, _: *Context) !void {
    const idx = MethodLookup.first_char[ctx_pm.method[0]];
    var radix = reverb.routes[idx];
    // this cuts almost half
    _ = radix.searchRoute(ctx_pm.path) catch return error.SearchRoute;

    // if (entry == null) {
    //     const ret_addr = @returnAddress();
    //     const debug_info = std.debug.getSelfDebugInfo() catch @panic("Could not get debug_info");
    //     // 1) Prepare a big enough buffer on the stack
    //     var buffer: [512]u8 = undefined;
    //     // 2) Wrap it in a FixedBufferStream
    //     var stream = std.io.fixedBufferStream(&buffer);
    //     const writer = stream.writer();
    //
    //     // 3) Call printSourceAtAddress into *your* writer
    //     const tty = std.io.tty.detectConfig(std.io.getStdErr());
    //     std.debug.printSourceAtAddress(debug_info, writer, ret_addr, tty) catch {};
    //
    //     const outSlice = buffer[0..stream.pos];
    //     const start = std.mem.indexOf(u8, outSlice, "src") orelse std.mem.indexOf(u8, outSlice, "std") orelse 0;
    //     const src = buffer[start..stream.pos];
    //     var sections = std.mem.splitScalar(u8, src, ':');
    //     var indents = std.mem.splitScalar(u8, src, '\n');
    //     const file_name = sections.next() orelse return;
    //     const line = sections.next() orelse return;
    //     const u32_line_n: u32 = std.fmt.parseInt(u32, line, 10) catch return;
    //     _ = indents.next().?;
    //     const fn_name = indents.next().?;
    //     const err_str = try std.fmt.allocPrint(reverb.arena.*, "{any}", .{error.MethodNotSupported});
    //     const function_name = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{fn_name[0 .. fn_name.len - 2]});
    //     const file_name_alloc = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{file_name});
    //     _ = Tripwire.Error{
    //         .timestamp = std.time.timestamp(),
    //         .error_name = err_str,
    //         .line = u32_line_n,
    //         .file = file_name_alloc,
    //         .request = ctx_pm.path,
    //         .function = function_name,
    //     };
    //     // Reverb.instance.tripwire.recordError(payload);
    //     return error.RouteNotSupported;
    // }
    // if (entry.?.route_func == null) {
    //     return error.MethodNotSupported;
    // }
    // const entry_fn = entry.?.route_func.?.handler_func;
    // const middlewares = entry.?.route_func.?.middlewares;
    // const param_args_op = entry.?.param_args;
    // if (param_args_op) |param_args| {
    //     if (param_args.items.len > 0) {
    //         for (param_args.items) |param| {
    //             ctx.addQueryParam(param.param, param.value) catch return error.AppendQueryParam;
    //         }
    //     }
    // }
    //
    // if (middlewares.len > 0) {
    //     parseMiddleWare(0, entry_fn, middlewares, ctx) catch return error.ParsingMiddleware;
    // } else {
    //     entry_fn(ctx) catch |err| {
    //         const ret_addr = @intFromPtr(entry_fn);
    //         const debug_info = std.debug.getSelfDebugInfo() catch @panic("Could not get debug_info");
    //         // 1) Prepare a big enough buffer on the stack
    //         var buffer: [512]u8 = undefined;
    //         // 2) Wrap it in a FixedBufferStream
    //         var stream = std.io.fixedBufferStream(&buffer);
    //         const writer = stream.writer();
    //
    //         // 3) Call printSourceAtAddress into *your* writer
    //         const tty = std.io.tty.detectConfig(std.io.getStdErr());
    //         std.debug.printSourceAtAddress(debug_info, writer, ret_addr, tty) catch {};
    //
    //         const outSlice = buffer[0..stream.pos];
    //         const start = std.mem.indexOf(u8, outSlice, "src") orelse std.mem.indexOf(u8, outSlice, "std") orelse 0;
    //         const src = buffer[start..stream.pos];
    //         var sections = std.mem.splitScalar(u8, src, ':');
    //         var indents = std.mem.splitScalar(u8, src, '\n');
    //         const file_name = sections.next() orelse return;
    //         const file_name_alloc = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{file_name});
    //         const line = sections.next() orelse return;
    //         const u32_line_n: u32 = std.fmt.parseInt(u32, line, 10) catch return;
    //         _ = indents.next().?;
    //         const fn_name = indents.next().?;
    //         const err_str = try std.fmt.allocPrint(reverb.arena.*, "{any}", .{error.MethodNotSupported});
    //         const function_name = try std.fmt.allocPrint(reverb.arena.*, "{s}", .{fn_name[0 .. fn_name.len - 2]});
    //         const payload = Tripwire.Error{
    //             .timestamp = std.time.timestamp(),
    //             .error_name = err_str,
    //             .line = u32_line_n,
    //             .file = file_name_alloc,
    //             .request = ctx_pm.path,
    //             .function = function_name,
    //         };
    //         Reverb.instance.tripwire.recordError(payload);
    //         return err;
    //     };
    // }
}

// Radix is a Radix tree routes is a hashmap with the method, each method has a radix tree
pub fn getRoute(t: *Reverb, ctx_pm: Ctx_pm) !?HandlerFunc {
    const idx = MethodLookup.first_char[ctx_pm.method[0]];
    var radix = t.routes[idx];
    // var op_method_rdx_tree: ?Radix = null;
    // op_method_rdx_tree = reverb.routes.get(ctx_pm.method);
    // var rdx_tree = op_method_rdx_tree orelse return null;
    // // const path = try reverb.arena.dupe(u8, ctx_pm.path);
    const entry = try radix.searchRoute(ctx_pm.path);
    if (entry == null) {
        return error.MethodNotSupported;
    }
    if (entry.?.route_func == null) {
        return error.MethodNotSupported;
    }
    const entry_fn: HandlerFunc = @ptrCast(entry.?.route_func.?.handler_func);
    // return apiTest;
    return entry_fn;
}

fn createContext(reverb: *Reverb, comptime T: type, data: T) !Context {
    const ctx = try Context.init(reverb.arena, data);
    return ctx;
}

/// This is the Cors struct default set to null
pub var cors: ?Cors = null;
pub fn new(target: *Reverb, config: Loom.Config, arena: *Allocator, ta: ?*TrackingAllocator) !void {
    var radix1: Radix = undefined;
    try radix1.init(arena);

    var radix2: Radix = undefined;
    try radix2.init(arena);

    var radix3: Radix = undefined;
    try radix3.init(arena);

    var radix4: Radix = undefined;
    try radix4.init(arena);

    var radix5: Radix = undefined;
    try radix5.init(arena);

    const routes_map = [5]Radix{ radix1, radix2, radix3, radix4, radix5 };
    var loom: Loom = undefined;
    try loom.new(config, arena, 0);

    var logger: Logger = undefined;
    logger.init();
    Buckets.init(arena);

    var buckets_thread = try std.Thread.spawn(.{}, Buckets.loop, .{});
    buckets_thread.detach();

    target.* = .{
        .config = config,
        .arena = arena,
        .routes = routes_map,
        .logger = logger,
        .loom = loom,
        .tracking_allocator = ta,
    };

    instance = target;
}

pub fn deinit(self: *Reverb) void {
    for (&self.routes) |*radix| {
        radix.deinit();
    }
    self.loom.deinit();
    if (Metrics.end_points.GET) |ep_get| {
        for (ep_get) |elem| {
            self.arena.free(elem);
        }
        self.arena.free(ep_get);
    }
    if (Metrics.end_points.POST) |ep_post| {
        for (ep_post) |elem| {
            self.arena.free(elem);
        }
        self.arena.free(ep_post);
    }
    if (Metrics.end_points.PATCH) |ep_patch| {
        for (ep_patch) |elem| {
            self.arena.free(elem);
        }
        self.arena.free(ep_patch);
    }
}

fn initTripwire(reverb: *Reverb) !void {
    reverb.tripwire.init(reverb.arena);
}

pub fn useTripwire(reverb: *Reverb) !void {
    reverb.tripwire.init(reverb.arena);
}

fn initMetrics(reverb: *Reverb) !void {
    // try metrics.mapRoutes();
    try reverb.addRoute("/metrics/allroutes", .GET, getAllRoutes, &[_]MiddleFunc{});
    try reverb.addRoute("/metrics/healthcheck", .GET, healthCheck, &[_]MiddleFunc{});
    // try nimbus.addRoute("/metrics/allroutes", "GET", Metrics.allEndPoints, &[_]MiddleFunc{});
    // try nimbus.addRoute("/metrics/server-status", "GET", dashboard.serverStatus, &[_]MiddleFunc{});
    // try nimbus.addRoute("/dashboard/request-metrics", "GET", dashboard.requestMetrics, &[_]MiddleFunc{});
}

pub fn useCors(_: *Reverb, corsConfig: Cors) !void {
    cors = corsConfig;
    use_cors = true;
}

/// This function calls listen on the Reverb instance.
///
/// # Returns:
/// !void.
pub fn listen(t: *Reverb) !void {
    try initMetrics(t);

    try t.logger.info("Listening on port {any}", .{t.config.server_port}, null);
    // try initTripwire(t);
    // defer t.tripwire.deinit();

    if (use_cors) {
        var str_builder = StringBuilder.new();
        try cors.?.checkHeadersStr(&str_builder);
        Context.cors_headers = str_builder.contents[str_builder.start..str_builder.len];
    }
    const loom = try t.arena.create(Loom);
    try loom.new(t.config, t.arena, 0);

    const ctx = try t.arena.create(Context);
    ctx.* = try Context.init(
        t.arena,
        "",
        "",
        null,
        null,
        ContentType.None,
        null,
        20,
    );
    ctx.id = 0;
    try Loom.listen(t, &t.loom, ctx);
}
