const std = @import("std");
const Client = @import("Client.zig");
const system = std.posix.system;
const posix = std.posix;
// struct kevent {
//     uintptr_t ident;      // What to monitor (like a file descriptor)
//     short     filter;     // What kind of event to watch for
//     u_short   flags;      // How to modify the registration
//     u_int     fflags;     // Extra filter-specific flags
//     intptr_t  data;       // Filter-specific data
//     void      *udata;     // Your custom data to attach
// };

pub const KQueue = @This();
kfd: posix.fd_t = undefined,
event_list: [1024]system.Kevent = undefined,
change_list: [128]system.Kevent = undefined,
change_count: usize = 0,

pub fn init() !KQueue {

    // This creates your event monitoring system. Think of it like setting up a notification center.
    // The returned kfd is your connection to this system
    // - all future communications about events will go through this file descriptor.
    const kfd = try posix.kqueue();
    return .{ .kfd = kfd };
}

pub fn deinit(self: KQueue) void {
    posix.close(self.kfd);
}

pub fn wait(self: *KQueue, timeout_ms: i32) ![]system.Kevent {
    const timeout = posix.timespec{
        .sec = @intCast(@divTrunc(timeout_ms, 1000)),
        .nsec = @intCast(@mod(timeout_ms, 1000) * 1000000),
    };

    // Here instead receive events, we pass teh eventlist to fill up
    // count tells us how many events occurred
    // timeout is how long we wait for events
    const count = try posix.kevent(
        self.kfd,
        self.change_list[0..self.change_count],
        &self.event_list,
        &timeout,
    );
    self.change_count = 0;
    return self.event_list[0..count];
}

pub fn addListener(self: *KQueue, listener: posix.socket_t) !void {
    std.debug.print("Registering listener fd={d} to kqueue={d}\n", .{ listener, self.kfd });
    // ok to use EV.ADD to renable the listener if it was previous
    // disabled via removeListener
    try self.queueChange(.{
        .ident = @intCast(listener),
        .filter = posix.system.EVFILT.READ,
        .flags = posix.system.EV.ADD,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    });
}

pub fn removeListener(self: *KQueue, listener: posix.socket_t) !void {
    try self.queueChange(.{
        .ident = @intCast(listener),
        .filter = posix.system.EVFILT.READ,
        .flags = posix.system.EV.DISABLE,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    });
}

pub fn newClient(self: *KQueue, client: *Client) !void {
    try self.queueChange(.{
        .ident = @intCast(client.socket),
        .filter = posix.system.EVFILT.READ,
        .flags = posix.system.EV.ADD | posix.system.EV.CLEAR, // I added CLEAR here
        .fflags = 0,
        .data = 0,
        .udata = @intFromPtr(client),
    });

    try self.queueChange(.{
        .ident = @intCast(client.socket),
        .filter = posix.system.EVFILT.WRITE,
        .flags = posix.system.EV.ADD | posix.system.EV.DISABLE,
        .fflags = 0,
        .data = 0,
        .udata = @intFromPtr(client),
    });
}

pub fn readMode(self: *KQueue, client: *Client) !void {
    try self.queueChange(.{
        .ident = @intCast(client.socket),
        .filter = posix.system.EVFILT.WRITE,
        .flags = posix.system.EV.DISABLE,
        .fflags = 0,
        .data = 0,
        .udata = @intFromPtr(client), // <-- Always pass the correct pointer
    });
    try self.queueChange(.{
        .ident = @intCast(client.socket),
        .filter = posix.system.EVFILT.READ,
        .flags = posix.system.EV.ENABLE,
        .fflags = 0,
        .data = 0,
        .udata = @intFromPtr(client),
    });
}

pub fn writeMode(self: *KQueue, client: *Client) !void {
    try self.queueChange(.{
        .ident = @intCast(client.socket),
        .filter = posix.system.EVFILT.READ,
        .flags = posix.system.EV.DISABLE,
        .fflags = 0,
        .data = 0,
        .udata = @intFromPtr(client), // <-- Always pass the correct pointer
    });

    try self.queueChange(.{
        .ident = @intCast(client.socket),
        .flags = posix.system.EV.ENABLE,
        .filter = posix.system.EVFILT.WRITE,
        .fflags = 0,
        .data = 0,
        .udata = @intFromPtr(client),
    });
}

pub fn addEventRaw(self: *KQueue, event: system.Kevent) !void {
    try self.queueChange(event);
}

// In your KQueue struct:
pub fn flushChanges(self: *KQueue) !void {
    if (self.change_count > 0) {
        _ = try posix.kevent(
            self.kfd,
            self.change_list[0..self.change_count],
            &.{}, // No events to receive
            null, // No timeout
        );
        self.change_count = 0;
    }
}

fn queueChange(self: *KQueue, event: system.Kevent) !void {
    // Here we take a new event and add it to the change_list
    var count = self.change_count;
    if (count == self.change_list.len) {
        // our change_list batch is full, apply it
        // This commits the batch change_list to the kqueue to watch these events;
        _ = try posix.kevent(self.kfd, &self.change_list, &.{}, null);
        count = 0;
    }
    self.change_list[count] = event;
    self.change_count = count + 1;
}
