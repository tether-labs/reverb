const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = std.posix;
const system = std.posix.system;
const print = std.debug.print;
const log = std.log.scoped(.tcp_demo);
const Logger = @import("Logger.zig");
const Parsed = std.json.Parsed;
const net = std.net;
const Signature = @import("async/Signature.zig");
const Scheduler = @import("async/Scheduler.zig");
const xresume = Scheduler.xresume;
const xsuspend = Scheduler.xsuspend;
const ThreadRipper = @import("async/pool/ThreadRipper.zig");
const Client = @import("Client.zig");
const KQueue = @import("KQueue.zig");
const Stack = @import("async/types.zig").Stack;
const process = @import("../handler.zig").handle;
const Context = @import("../context.zig");
const Tether = @import("../server.zig");
const dom = @import("../core/simdjson/dom.zig");

// EVFILT_READ
// Monitors for data available to read
// For sockets: triggers when data arrives
// For files: triggers when data is available
// The .data field will contain number of bytes available

// EVFILT_WRITE
// Monitors for write space available
// Triggers when buffer space is available for writing
// .data field contains space available in buffer

// EVFILT_AIO
// For asynchronous I/O operations
// Monitors completion of aio_* functions
// Great for bulk file operations

// EVFILT_VNODE
// Monitors changes to files and directories
// Can detect: delete, write, extend, attrib, link, rename
// Commonly used for config file monitoring

// EVFILT_PROC
// Monitors process events
// Can detect: exit, fork, exec, signal
// Useful for process supervision

// EVFILT_SIGNAL
// Monitors for Unix signals
// Alternative to traditional signal handlers
// More flexible than signal()

// EVFILT_TIMER
// Creates a timer event
// Can be one-shot or periodic
// More efficient than multiple individual timers

// EVFILT_USER
// User-triggered events
// Allows triggering events from userspace
// Useful for inter-thread communication

// EV_ADD
// Add an event to kqueue monitoring
// If it exists, modify it
// Most common flag you'll use

// EV_DELETE
// Remove event from monitoring
// Stops watching for this event
// Use when cleaning up

// EV_ENABLE
// Enable an event that was disabled
// Event can now trigger
// Paired with EV_DISABLE

// EV_DISABLE
// Temporarily disable event
// Event won't trigger until enabled
// Good for temporary suspensions

// EV_ONESHOT
// Only trigger once
// Automatically removed after triggering
// Good for one-time notifications

// EV_CLEAR
// Clear event state after triggering
// Prevents edge-triggered notification pileup
// Important for high-throughput scenarios

// EV_EOF
// End of file condition
// Set by system when EOF detected
// Useful for connection handling

// EV_ERROR
// Error condition
// Set by system when error occurs
// Check errno for details

// 1 minute
const READ_TIMEOUT_MS = 60_000;
// const READ_TIMEOUT_MS = 0;

const ClientList = std.DoublyLinkedList(*Client);
const ClientNode = ClientList.Node;
pub var logger: Logger = undefined;
pub var loom_engine: Scheduler = undefined;

pub const Loom = @This();
id: usize = 0,
arena: *Allocator = undefined,
config: Config = undefined,
// Max connections
max: usize = undefined,

listener: *posix.socket_t = undefined,

// Event Loop
kqueue: KQueue = undefined,

// The number of clients we currently have connected
connected: u32 = undefined,

read_timeout_list: ClientList = undefined,

// for creating client
client_pool: std.heap.MemoryPool(Client) = undefined,
context_pool: std.heap.MemoryPool(Context) = undefined,
// for creating nodes for our read_timeout list
client_node_pool: std.heap.MemoryPool(ClientList.Node) = undefined,
fiber: FiberGen = undefined,
scheduler: Scheduler = undefined,
stack: Stack = undefined,

pub const Config = struct {
    server_addr: []const u8,
    server_port: u16,
    sticky_server: bool,
    tls: bool,
    max: usize = 16384,
};

/// This is the Cors struct default set to null
const FiberGen = Signature.fromFunc(listen, .{ .YieldT = *Conn, .InjectT = *Conn });
pub fn new(target: *Loom, config: Config, arena: *Allocator, id: usize) !void {
    var scheduler: Scheduler = undefined;
    try scheduler.init(arena.*);
    loom_engine = scheduler;

    logger.init();
    var loom = Loom{
        .id = id,
        .config = config,
        .arena = arena,
        .max = config.max,
        // .kqueue = kqueue,
        .connected = 0,
        .read_timeout_list = .{},
        .client_pool = std.heap.MemoryPool(Client).init(arena.*),
        .context_pool = std.heap.MemoryPool(Context).init(arena.*),
        .client_node_pool = std.heap.MemoryPool(ClientNode).init(arena.*),
        .scheduler = scheduler,
    };
    // We need to find a way to determine the size of the stack
    // This is important since the corutine switch between theloom
    const stack = try scheduler.stackAlloc(1024 * 10);
    // const fiber = try FiberGen.init(.{&loom}, stack);
    // loom.fiber = fiber;
    loom.stack = stack;
    target.* = loom;
}

pub fn deinit(self: *Loom) void {
    self.kqueue.deinit();
    self.client_pool.deinit();
    self.client_node_pool.deinit();
    self.arena.free(self.stack);
    // self.scheduler.deinit();
}

pub fn createListener(loom: *Loom) !c_int {
    // const self_addr = try net.Address.resolveIp(loom.config.server_addr, loom.config.server_port);
    const self_addr = try net.Address.resolveIp(loom.config.server_addr, loom.config.server_port);

    // 1. Create non-blocking socket
    const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
    const listener = try posix.socket(self_addr.any.family, tpe, posix.IPPROTO.TCP);

    // 2. Set REUSEPORT FIRST (MUST BE BEFORE BIND)
    const reuse = std.mem.toBytes(@as(c_int, 1));
    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEPORT, &reuse);
    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &reuse);

    // 3. Bind and listen
    try posix.bind(listener, &self_addr.any, self_addr.getOsSockLen());
    try posix.listen(listener, 4096);

    // 4. Add to THIS THREAD'S kqueue (not a shared one)
    try loom.kqueue.addListener(listener);

    // 5. Force flush kqueue changes immediately
    try loom.kqueue.flushChanges();

    return listener;
}

const Conn = struct {
    client: *Client = undefined,
    msg: []const u8 = "",
    received: bool = false,
};

pub fn accept(self: *Loom) ?*Conn {
    const value = self.fiber.xnextNoop();
    if (value.received) {
        return value;
    }
    return null;
}

// const red = "\x1b[91m"; // ANSI escape code for red color
// const yellow = "\x1b[93m"; // ANSI escape code for red color
// const yellow = "\x1b[36m";
// const background = "\x1b[36m"; // ANSI escape code for red color
// const reset = "\x1b[0m"; // ANSI escape code to reset color
// const bold = "\x1b[1m"; // ANSI escape code to reset color

// const ascii_art =
//     \\ ______   ______     ______   __  __     ______     ______
//     \\/\__  _\ /\  ___\   /\__  _\ /\ \_\ \   /\  ___\   /\  == \
//     \\\/_/\ \/ \ \  __\   \/_/\ \/ \ \  __ \  \ \  __\   \ \  __<
//     \\   \ \_\  \ \_____\    \ \_\  \ \_\ \_\  \ \_____\  \ \_\ \_\
//     \\    \/_/   \/_____/     \/_/   \/_/\/_/   \/_____/   \/_/ /_/
// ;
//
// print("\n{s}{s}{s}{s}\n\n", .{ bold, yellow, ascii_art, reset });

// try logger.info(
//     "{s}{s}Running  {s}:{}{s}",
//     .{ bold, background, loom.config.server_addr, loom.config.server_port, reset },
//     @src(),
// );

// var thread = try std.Thread.spawn(.{}, run, .{ loom, listener });
// thread.detach();
// while (true) {}

// for (0..4) |i| {
//     // const inner_loom = try t.arena.create(Loom);
//     // try inner_loom.new(
//     //     .{
//     //         .tls = false,
//     //         .server_addr = loom.config.server_addr,
//     //         .server_port = loom.config.server_port,
//     //         .sticky_server = false,
//     //     },
//     //     t.arena,
//     //     i,
//     // );
//     // inner_loom.listener = &listener;
//     // try loom.kqueue.addListener(listener);
//     const inner_ctx = try t.arena.create(Context);
//     inner_ctx.* = try Context.init(
//         t.arena,
//         "",
//         "",
//         null,
//         null,
//         "",
//         null,
//     );
//     inner_ctx.id = i;
//     // try t.loom.multi(t, &inner_ctx);
//     try multi(loom, listener, t, inner_ctx);
// }
// while (true) {}

/// This function calls listen on the Loom instance.
///
/// # Returns:
/// !void.
pub fn listen(t: *Tether, loom: *Loom, ctx: *Context) !void {
    var kqueue = try KQueue.init();
    errdefer kqueue.deinit();
    loom.kqueue = kqueue;
    const listener = loom.createListener() catch return;
    // Verify unique resources
    std.debug.assert(loom.kqueue.kfd == kqueue.kfd);
    try run(t, loom, listener, ctx);
}

const resp = "HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nHello, world";
fn run(
    t: *Tether,
    loom: *Loom,
    listener: posix.socket_t,
    ctx: *Context,
) !void {
    const options = ThreadRipper.Options{ .arena = t.arena.*, .max_threads = 4 };

    try loom.scheduler.atm_pool.init(options);
    // var read_timeout_list = &loom.read_timeout_list;

    // var ctxs = try t.arena.alloc(*Context, 4);
    // for (0..4) |i| {
    //     const inner_ctx = try t.arena.create(Context);
    //     inner_ctx.* = try Context.init(
    //         t.arena,
    //         "",
    //         "",
    //         null,
    //         null,
    //         "",
    //         null,
    //     );
    //     inner_ctx.id = i;
    //     ctxs[i] = inner_ctx;
    // }
    // loom.scheduler.atm_pool.warm_with_ctx(ctxs);

    // var accept_: bool = false;
    while (true) {
        const next_timeout = loom.enforceTimeout();
        const ready_events = loom.readEvents(next_timeout) catch return;
        for (ready_events) |ready| {
            // ready is type kevent
            // udata is the client conn value
            switch (ready.udata) {
                // 0 is the listener socket so here if we receive a notification
                // from the listener socket then we need to accept a new conn and add it to the kqueue
                // else we are reading a new conn
                0 => loom.acceptConn(listener) catch |err| log.err(
                    "failed to accept: {}",
                    .{err},
                ),
                else => |nptr| {
                    const client: *Client = @ptrFromInt(nptr);
                    const filter = ready.filter;

                    // Here we read in the client data
                    // we check the filter state
                    if (filter == system.EVFILT.READ) {
                        // Here we read and write

                        while (true) {
                            const msg = client.readMessage() catch |err| {
                                switch (err) {
                                    error.WouldBlock => {
                                        break;
                                    },
                                    else => {
                                        loom.closeClient(client);
                                        break;
                                    },
                                }
                            };

                            // client.read_timeout = std.time.milliTimestamp() + READ_TIMEOUT_MS;
                            // read_timeout_list.remove(client.read_timeout_node);
                            // read_timeout_list.append(client.read_timeout_node);

                            try process(client, msg, ctx);

                            // const job_context = try loom.context_pool.create();
                            // job_context.* = try Context.init(
                            //     loom.arena,
                            //     "",
                            //     "",
                            //     null,
                            //     null,
                            //     "",
                            //     null,
                            // );
                            // const node = try loom.scheduler.atm_pool.generateJobWithCtx(process, .{ client, msg });
                            // try loom.scheduler.atm_pool.dispatchJob(node);
                            // if (!accept_) {
                            //     print("Loop Id: {any}\n", .{ctx.id});
                            //     print("Loop kfd: {any}\n", .{loom.kqueue.kfd});
                            //     print("Loop Listener: {any}\n", .{listener});
                            //     accept_ = true;
                            // }

                            // try test_thread(client);
                            // _ = posix.write(client.socket, resp) catch |err| {
                            //     print("Write Error: {any}\n", .{err});
                            // };
                        }
                    } else if (filter == system.EVFILT.WRITE) {
                        // If we couldn't write for some reason initially then
                        // when we receive a write event we write to the client
                        loom.closeClient(client);
                    }
                },
            }
        }
    }
}

pub fn enforceTimeout(self: *Loom) i32 {
    const now = std.time.milliTimestamp();
    var node = self.read_timeout_list.first;
    while (node) |n| {
        const client = n.data;
        const diff = client.read_timeout - now;
        if (diff > 0) {
            // this client's timeout is the first one that's in the
            // future, so we now know the maximum time we can block on
            // poll before having to call enforceTimeout again
            return @intCast(diff);
        }

        // This client's timeout is in the past. Close the socket
        // Ideally, we'd call server.removeClient() and just remove the
        // client directly. But within this method, we don't know the
        // client_polls index. When we move to epoll / kqueue, this problem
        // will go away, since we won't need to maintain polls and client_polls
        // in sync by index.
        posix.shutdown(client.socket, .recv) catch {};
        node = n.next;
    } else {
        // We have no client that times out in the future (if we did
        // we would have hit the return above).
        return -1;
    }
}

pub fn acceptConn(self: *Loom, listener: posix.socket_t) !void {
    var address: net.Address = undefined;
    var address_len: posix.socklen_t = @sizeOf(net.Address);
    // const space = self.max - self.connected;
    if (self.connected < self.max) {
        const socket = posix.accept(listener, &address.any, &address_len, posix.SOCK.NONBLOCK) catch |err| switch (err) {
            error.WouldBlock => return,
            else => return err,
        };

        const client = try self.client_pool.create();
        errdefer self.client_pool.destroy(client);
        client.* = Client.init(self.arena.*, socket, address, &self.kqueue) catch |err| {
            posix.close(socket);
            log.err("failed to initialize client: {}", .{err});
            return;
        };
        errdefer client.deinit(self.arena.*);

        client.read_timeout = std.time.milliTimestamp() + READ_TIMEOUT_MS;
        client.read_timeout_node = try self.client_node_pool.create();
        errdefer self.client_node_pool.destroy(client.read_timeout_node);

        client.read_timeout_node.* = .{
            .next = null,
            .prev = null,
            .data = client,
        };

        self.read_timeout_list.append(client.read_timeout_node);
        try self.kqueue.newClient(client);
        self.connected += 1;
    } else {
        print("We Ran out of space\n", .{});
        // we've run out of space, stop monitoring the listening socket
        try self.kqueue.removeListener(listener);
    }
}

pub fn readEvents(loom: *Loom, next_timeout: i32) ![]system.Kevent {
    return try loom.kqueue.wait(next_timeout);
}

pub fn closeClient(self: *Loom, client: *Client) void {
    self.read_timeout_list.remove(client.read_timeout_node);
    self.client_node_pool.destroy(client.read_timeout_node);
    client.deinit(self.arena.*);
    posix.close(client.socket);
    self.client_pool.destroy(client);
    self.connected -= 1;
}
