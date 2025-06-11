const std = @import("std");
const Alignment = std.mem.Alignment;
const BITS_IN_BYTE = 8;
const BYTES_IN_MEGABYTE = 1000;

//Prints the size in bytes of a type with a size
//Example: i32 = 4 bytes number = 100
//4 * 100 = 400 bytes
pub fn printSizeInBytes(comptime T: type, number: usize) void {
    const SIZE_IN_BYTES = @sizeOf(T) * number;
    std.debug.print("     size: {} bytes\n", .{SIZE_IN_BYTES});
}

const MemoryDeets = struct {
    fn_breadcrumb: []const u8,
    bytes: usize,
    file_name: []const u8,
};

pub const TrackingAllocator = @This();
base: std.mem.Allocator,
allocated_bytes: usize,
_allocations_map: std.AutoHashMap([*]u8, MemoryDeets),
_runtime_allocation_map: std.AutoHashMap([*]u8, MemoryDeets),
_start_bytes_size: usize = 0,
_is_runtime: bool = false,
_log: bool = false,

//Creates the Tracking Allocator
pub fn init(ta: *TrackingAllocator, allocator: std.mem.Allocator) std.mem.Allocator {
    ta.* = .{
        .allocated_bytes = 0,
        .base = allocator,
        ._allocations_map = std.AutoHashMap([*]u8, MemoryDeets).init(allocator),
        ._runtime_allocation_map = std.AutoHashMap([*]u8, MemoryDeets).init(allocator),
    };

    return std.mem.Allocator{
        .ptr = ta,
        .vtable = &.{
            .alloc = alloc,
            .free = free,
            .resize = resize,
            .remap = remap,
        },
    };
}

pub fn deinit(ta: *TrackingAllocator) void {
    // var alloc_itr = ta._allocations_map.iterator();
    // while (alloc_itr.next()) |sym| {
    //     sym.value_ptr.symbol
    // }
    ta._allocations_map.deinit();
    ta._runtime_allocation_map.deinit();
}

pub fn alloc(
    self: *anyopaque,
    len: usize,
    alignment: Alignment,
    ret_addr: usize,
) ?[*]u8 {
    // const addr = @returnAddress();
    const ta: *TrackingAllocator = @ptrCast(@alignCast(self));
    ta.allocated_bytes += len;
    const slice = ta.base.rawAlloc(len, alignment, ret_addr);
    ta.printAllocStackTrace(ret_addr, len, slice);
    return slice;
}

fn printAllocStackTrace(ta: *TrackingAllocator, ret_addr: usize, bytes: usize, ptr_op: ?[*]u8) void {
    if (ptr_op == null) return;
    const ptr = ptr_op.?;

    const debug_info = std.debug.getSelfDebugInfo() catch @panic("Could not get debug_info");
    // 1) Prepare a big enough buffer on the stack
    var buf: [512]u8 = undefined;
    // 2) Wrap it in a FixedBufferStream
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // 3) Call printSourceAtAddress into *your* writer
    const tty = std.io.tty.detectConfig(std.io.getStdErr());
    std.debug.printSourceAtAddress(debug_info, writer, ret_addr, tty) catch {};

    // 4) Grab only the bytes that were written
    const outSlice = buf[0..stream.pos];
    const start = std.mem.indexOf(u8, outSlice, "src") orelse std.mem.indexOf(u8, outSlice, "std") orelse 0;
    const src = buf[start..stream.pos];
    var sections = std.mem.splitScalar(u8, src, ':');
    const file_name = sections.next() orelse return;
    const line = sections.next() orelse return;
   if (ta._log) {
        std.debug.print("\x1b[1m\x1b[36mAlloc \x1b[0m\x1b[22m[\x1b[35m{any}\x1b[0m] {any} bytes | {s}:{s}\n", .{
            ptr,
            bytes,
            file_name,
            line,
        });
    }
    const mem_deets = MemoryDeets{
        .file_name = file_name,
        .bytes = bytes,
        .fn_breadcrumb = line,
    };
    if (ta._is_runtime) {
        var old_mem_deets = ta._runtime_allocation_map.get(ptr) orelse {
            ta._runtime_allocation_map.put(ptr, mem_deets) catch return;
            return;
        };
        old_mem_deets.bytes += bytes;
        return;
    }
    var old_mem_deets = ta._runtime_allocation_map.get(ptr) orelse {
        ta._allocations_map.put(ptr, mem_deets) catch return;
        return;
    };
    old_mem_deets.bytes += bytes;
}

fn printFreeStackTrace(ta: *TrackingAllocator, ret_addr: usize, bytes: usize, ptr: [*]u8) void {
    const debug_info = std.debug.getSelfDebugInfo() catch @panic("Could not get debug_info");
    // 1) Prepare a big enough buffer on the stack
    var buf: [512]u8 = undefined;
    // 2) Wrap it in a FixedBufferStream
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // 3) Call printSourceAtAddress into *your* writer
    const tty = std.io.tty.detectConfig(std.io.getStdErr());
    std.debug.printSourceAtAddress(debug_info, writer, ret_addr, tty) catch {};

    // 4) Grab only the bytes that were written
    const outSlice = buf[0..stream.pos];
    const start = std.mem.indexOf(u8, outSlice, "src") orelse std.mem.indexOf(u8, outSlice, "std") orelse 0;
    const src = buf[start..stream.pos];
    var sections = std.mem.splitScalar(u8, src, ':');
    const file_name = sections.next() orelse return;
    const line = sections.next() orelse return;

    if (ta._log) {
        std.debug.print("\x1b[1m\x1b[33mFree \x1b[0m\x1b[22m[\x1b[35m{any}\x1b[0m] {any} bytes | {s}:{s}\n", .{
            ptr,
            bytes,
            file_name,
            line,
        });
    }
    if (ta._is_runtime) {
        var old_mem_deets = ta._runtime_allocation_map.get(ptr) orelse {
            std.debug.print("Could not free, no allocation [\x1b[35m{any}\x1b[0m] {any} bytes\n", .{ ptr, bytes });
            return;
            // @panic("Invalid free");
        };
        if (old_mem_deets.bytes - bytes == 0) {
            _ = ta._runtime_allocation_map.remove(ptr);
            return;
        }
        old_mem_deets.bytes -= bytes;
        return;
    }
    var old_mem_deets = ta._allocations_map.get(ptr) orelse {
        std.debug.print("Could not free, no allocation\n", .{});
        return;
        // @panic("Invalid free");
    };
    if (old_mem_deets.bytes > bytes and old_mem_deets.bytes - bytes == 0) {
        _ = ta._allocations_map.remove(ptr);
        return;
    }
    if (old_mem_deets.bytes > bytes) {
        old_mem_deets.bytes -= bytes;
    }
    // }
}

fn resize(
    self: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) bool {
    const ta: *TrackingAllocator = @ptrCast(@alignCast(self));
    const old_len = memory.len;
    if (new_len == 0) {
        // free case:
        free(self, memory, alignment, ret_addr);
        return true;
    }
    if (old_len == 0) {
        return false;
    }
    if (ta.base.rawResize(memory, alignment, new_len, ret_addr)) {
        // std.debug.print("Resizing\n", .{});
        if (new_len > old_len) {
            ta.allocated_bytes += (new_len - old_len);
        } else {
            ta.allocated_bytes -= (old_len - new_len);
        }
        return true;
    }
    return false;
}

fn free(
    self: *anyopaque,
    memory: []u8,
    alignment: Alignment,
    ret_addr: usize,
) void {
    const ta: *TrackingAllocator = @ptrCast(@alignCast(self));
    ta.allocated_bytes -= memory.len;

    ta.printFreeStackTrace(ret_addr, memory.len, memory.ptr);
    ta.base.rawFree(memory, alignment, ret_addr);
}

fn remap(
    self: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) ?[*]u8 {
    const ta: *TrackingAllocator = @ptrCast(@alignCast(self));
    const old_len = memory.len;
    if (new_len == 0) {
        free(self, memory, alignment, ret_addr);
        return memory[0..0];
    }
    if (old_len == 0) {
        return null;
    }
    const p = ta.base.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
    if (new_len > old_len) {
        ta.allocated_bytes += (new_len - old_len);
    } else {
        ta.allocated_bytes -= (old_len - new_len);
    }
    return p;
}

pub fn bytesAllocated(self: *TrackingAllocator) usize {
    return self.allocated_bytes;
}

pub fn checkAllocation(ta: *TrackingAllocator) void {
    std.debug.print("\n\x1b[1m\x1b[33mTotal Allocations\x1b[0m\x1b[22m\n", .{});
    std.debug.print("Total Memory: {} bytes\n", .{ta.allocated_bytes});
    std.debug.print("Start Up Bytes Size: {} bytes\n", .{ta._start_bytes_size});
    std.debug.print("-------------------------------------------\n", .{});
    std.debug.print("\x1b[37mStartup Allocations:\x1b[0m\n", .{});
    var itr = ta._allocations_map.iterator();
    var total_size: usize = 0;
    while (itr.next()) |entry| {
        const key = entry.key_ptr.*;
        const mem_deets = entry.value_ptr.*;
        std.debug.print("\x1b[1m\x1b[36mAlloc \x1b[0m\x1b[22m[\x1b[35m{any}\x1b[0m] | Memory: {any} bytes\n", .{ key, mem_deets.bytes });
        total_size += mem_deets.bytes;
    }
    // std.debug.print("-------------------------------------------\n", .{});
    // std.debug.print("Total Runtime Memory: {} bytes\n", .{ta.allocated_bytes - ta._start_bytes_size});
    std.debug.print("-------------------------------------------\n", .{});
    std.debug.print("\x1b[37mRuntime Allocations:\x1b[0m\n", .{});
    var run_time_itr = ta._runtime_allocation_map.iterator();
    while (run_time_itr.next()) |entry| {
        const key = entry.key_ptr.*;
        const mem_deets = entry.value_ptr.*;
        std.debug.print("\x1b[1m\x1b[36mRuntime-Alloc \x1b[0m\x1b[22m[\x1b[35m{any}\x1b[0m] | Memory: {any} bytes\n", .{ key, mem_deets.bytes });
    }
    std.debug.print("-------------------------------------------\n", .{});
}

pub fn printBytes(self: TrackingAllocator) void {
    std.debug.print("Memory: {} bytes\n", .{self.allocated_bytes});
}

pub fn printBits(self: TrackingAllocator) void {
    std.debug.print("     Memory: {} bits\n", .{self.allocated_bytes * BITS_IN_BYTE});
}

pub fn printMegaBytes(self: TrackingAllocator) void {
    const ALLOCATED_BYTES_U64: f64 = @floatFromInt(self.allocated_bytes);
    const SIZE_IN_MEGABYTES: f64 = ALLOCATED_BYTES_U64 / @as(f64, BYTES_IN_MEGABYTE);

    std.debug.print("     Memory: {d:.3}", .{SIZE_IN_MEGABYTES});
}

test "alloc" {
    var ta: TrackingAllocator = undefined;
    var allocator = ta.init(std.testing.allocator);
    const arr = try allocator.alloc([]const u8, 10);
    allocator.free(arr);
    const heap_node = try allocator.create(struct { int: u64 });
    allocator.destroy(heap_node);
    var map = std.StringHashMap([]const u8).init(allocator);
    try map.put("hlloe", "falksdfjlakdfj");
    map.deinit();
}
