const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;
const KQueue = @import("KQueue.zig");
const Loom = @import("Loom.zig");

const ClientList = std.DoublyLinkedList(*Client);
const ClientNode = ClientList.Node;

pub const Client = @This();
kqueue: *KQueue,

socket: posix.socket_t,
address: std.net.Address,

// Used to read length-prefixed messages
msg: []const u8,

// Used to write messages
writer: Writer,
response: []const u8,

// absolute time, in millisecond, when this client should timeout if
// a message isn't received
read_timeout: i64,

// Node containing this client in the server's read_timeout_list
read_timeout_node: *ClientNode,

pub fn init(arena: Allocator, socket: posix.socket_t, address: std.net.Address, kqueue: *KQueue) !Client {
    // const reader = try Reader.init(arena, 4096);
    // errdefer reader.deinit(arena);

    const writer = try Writer.init(arena, 4096);
    errdefer writer.deinit(arena);

    // const write_buf = try arena.alloc(u8, 4096);
    // errdefer arena.free(write_buf);

    return .{
        .kqueue = kqueue,
        .socket = socket,
        .address = address,
        .msg = "",
        .writer = writer,
        .response = "",
        .read_timeout = 0, // let the server set this
        .read_timeout_node = undefined, // hack/ugly, let the server set this when init returns
    };
}

pub fn deinit(_: *const Client, _: Allocator) void {
    // self.writer.deinit(arena);
}

fn findEndOfHeaders(buffer: []const u8) ?usize {
    // Need at least 4 bytes for \r\n\r\n
    if (buffer.len < 4) return null;

    // Use a sliding window of 4 bytes
    var i: usize = 0;
    while (i <= buffer.len - 4) : (i += 1) {
        // Check all 4 bytes at once
        if (buffer[i] == '\r' and
            buffer[i + 1] == '\n' and
            buffer[i + 2] == '\r' and
            buffer[i + 3] == '\n')
        {
            return i + 4; // Return position after the sequence
        }
    }
    return null;
}

pub fn findCRLFCRLF(payload: []const u8) ?usize {
    if (payload.len < 4) return null;

    if (payload.len >= 32) {
        const V = @Vector(32, u8);
        const cr_pattern: V = @splat('\r');
        var i: usize = 0;

        while (i + 32 <= payload.len) : (i += 32) {
            const chunk: V = payload[i..][0..32].*;
            const cr_matches = chunk == cr_pattern;
            const cr_mask: u32 = @bitCast(cr_matches);

            if (cr_mask != 0) {
                var mask = cr_mask;
                while (mask != 0) {
                    const pos = i + @ctz(mask);
                    if (pos + 3 < payload.len and
                        payload[pos + 1] == '\n' and
                        payload[pos + 2] == '\r' and
                        payload[pos + 3] == '\n')
                    {
                        return pos;
                    }
                    mask &= mask - 1;
                }
            }
        }

        // Check remaining bytes after last 32-byte chunk
        i -= 3; // Ensure we check overlapping with the last chunk's end
        while (i < payload.len - 3) : (i += 1) {
            if (payload[i] == '\r' and
                payload[i + 1] == '\n' and
                payload[i + 2] == '\r' and
                payload[i + 3] == '\n')
            {
                return i;
            }
        }
        return null;
    }

    // Non-SIMD path for small payloads
    var i: usize = 0;
    while (i <= payload.len - 4) : (i += 1) {
        if (payload[i] == '\r' and
            payload[i + 1] == '\n' and
            payload[i + 2] == '\r' and
            payload[i + 3] == '\n')
        {
            return i;
        }
    }
    return null;
}

var reader_buf: [2097152]u8 = [_]u8{0} ** 2097152;
pub fn readMessage(self: *Client) ![]const u8 {
    // return self.reader.readMessage(self.socket) catch |err| {
    //     // try Loom.logger.err("Read msg {any}", .{err}, @src());
    //     switch (err) {
    //         error.WouldBlock => return null,
    //         else => return err,
    //     }
    // };

    const rv = try posix.read(self.socket, &reader_buf);
    if (rv == 0) {
        return error.Closed;
    }

    // var end = buf[0..rv].len;
    // std.debug.print("{s}\n", .{buf[0..rv]});
    // if (buf[end - 1] != 10) {
    //     // std.debug.print("H\n", .{});
    //     end = findCRLFCRLF(buf[0..rv]).?;
    //     // std.debug.print("{any}\n", .{end});
    // }

    return reader_buf[0..rv];
}

pub fn writeMessage(self: *Client, _: []const u8) !?void {
    return self.writer.writeMessage(self.socket) catch |err| {
        switch (err) {
            error.WouldBlock => {
                try self.kqueue.writeMode(self);
                return null;
            },
            else => return err,
        }
    };

    // self.pos = msg.len;
    // @memcpy(self.buf[self.start..self.pos], msg);
    // var buf = self.buf;
    // const pos = self.pos;
    // const start = self.start;
    // std.debug.assert(pos >= start);
    // const wv = posix.write(self.socket, msg) catch |err| {
    //     switch (err) {
    //         error.WouldBlock => {
    //             try self.kqueue.writeMode(self);
    //             return null;
    //         },
    //         else => return err,
    //     }
    // };
    // if (wv == 0) {
    //     return error.Closed;
    // }

    // self.writer.buf = undefined;
}

pub fn fillWriteBuffer(self: *Client, msg: []const u8) !void {
    self.writer.fillWriteBuffer(msg) catch |err| {
        try Loom.logger.err("Fill write buffer {any}", .{err}, @src());
        return error.FailedToFillClientBuf;
    };
}

pub fn handle(client: *Client) !void {
    while (true) {
        const msg = client.readMessage() catch |err| {
            switch (err) {
                error.WouldBlock => {
                    break;
                },
                else => {
                    posix.close(client.socket);
                    // loom.closeClient(client);
                    break;
                },
            }
        };

        // client.read_timeout = std.time.milliTimestamp() + READ_TIMEOUT_MS;
        // read_timeout_list.remove(client.read_timeout_node);
        // read_timeout_list.append(client.read_timeout_node);

        client.fillWriteBuffer(msg) catch |err| {
            std.debug.print("Fill Error: {any}\n", .{err});
        };
        _ = client.writeMessage() catch |err| {
            std.debug.print("Write Error: {any}\n", .{err});
            // loom.closeClient(client);
            posix.close(client.socket);
            break;
        };

        // var conn = Conn{
        //     .client = client,
        //     .msg = msg,
        //     .received = true,
        // };
        // _ = FiberGen.xyield(&conn);
    }
}

const Reader = struct {
    buf: [4096]u8 = [_]u8{0} ** 4096,
    pos: usize = 0,
    start: usize = 0,

    pub fn init(_: Allocator, _: usize) !Reader {
        // const buf = try arena.alloc(u8, size);
        return .{
            .pos = 0,
            .start = 0,
            // .buf = buf,
        };
    }

    pub fn deinit(_: *const Reader, _: Allocator) void {
        // arena.free(self.buf);
    }

    // !!!!!!!!!!!!!!!This process of adding is extremely heavy
    // self.pos += rv;
    pub fn readMessage(self: *Reader, socket: posix.socket_t) ![]u8 {
        var buf = self.buf;
        const start = self.start;

        const rv = try posix.read(socket, buf[start..]);
        if (rv == 0) {
            return error.Closed;
        }

        self.pos = rv;
        std.debug.assert(self.pos >= start);
        const msg = buf[start..self.pos];
        self.start += msg.len;
        return msg;
    }
};

var writer_buf: [4096]u8 = [_]u8{0} ** 4096;
const Writer = struct {
    buf: []u8,
    pos: usize = 0,
    start: usize = 0,

    pub fn init(_: Allocator, _: usize) !Writer {
        // const buf = try arena.alloc(u8, size);
        return .{
            .buf = &writer_buf,
            .pos = 0,
            .start = 0,
        };
    }

    pub fn deinit(_: *const Writer, _: Allocator) void {
        // arena.free(self.buf);
    }

    pub fn fillWriteBuffer(self: *Writer, msg: []const u8) !void {
        self.pos += msg.len;
        // self.pos = msg.len;
        @memcpy(self.buf[self.start..self.pos], msg);
        self.start += msg.len;
    }

    pub fn writeMessage(self: *Writer, socket: posix.socket_t) !void {
        var buf = self.buf;
        const pos = self.pos;
        const start = self.start;
        std.debug.assert(pos >= start);
        const wv = posix.write(socket, buf[0..pos]) catch |err| {
            switch (err) {
                error.WouldBlock => return error.WouldBlock,
                else => return err,
            }
        };
        if (wv == 0) {
            return error.Closed;
        }
        std.log.debug("{any} {any}\n", .{ self.start, self.pos });
        // self.pos = pos + wv;
        self.start = 0;
        self.pos = 0;
        // self.buf = undefined;
    }
};
