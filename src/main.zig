//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const Server = @import("lib/server.zig");
const Context = @import("lib/context.zig");
const Loom = @import("lib/engine/Loom.zig");
const Scheduler = @import("lib/engine/async/Scheduler.zig");
const createFiber = Scheduler.createFiber;
const activate = Scheduler.activate;
const xresume = Scheduler.xresume;
const xsuspend = Scheduler.xsuspend;

const Next = Server.Next;
var loom: Loom = undefined;

fn fiber_response(ctx: *Context) !void {
    try ctx.STRING("SUCCESS");
    // Suspends this fiber and resumes the calling fiber
    // xsuspend();
}

fn ping(ctx: *Context) !void {
    // const stack = try loom.scheduler.stackAlloc(null);
    // defer loom.scheduler.freeStack(stack);
    // const fiber = try createFiber(fiber_response, .{ctx}, stack);
    try ctx.STRING("SUCCESS");
    // We start the fiber
    // activate(fiber);
}

pub fn main() !void {
    var server: Server = undefined;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("Memmory leak...");
    var allocator = gpa.allocator();

    const loom_config = Server.Config{
        .max = 1024,
    };

    try server.new(loom_config, &allocator, null);
    try server.get("/ping", ping, &.{});

    loom = Server.instance.loom;

    try server.listen();
}
