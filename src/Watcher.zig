const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const windows = os.windows;
const posix = std.posix;
const system = posix.system;
const mem = std.mem;
const Allocator = mem.Allocator;
const native_os = builtin.os.tag;
const fd_t = system.fd_t;

const EPOLL_CTL_ADD = 1;
const IN_NONBLOCK = 0x800;
const IN_ISDIR = 0x40000000;

const IN_ACCESS = 0x00000001;
const IN_MODIFY = 0x00000002;
const IN_ATTRIB = 0x00000004;
const IN_CLOSE_WRITE = 0x00000008;
const IN_CLOSE_NOWRITE = 0x00000010;
const IN_CLOSE = IN_CLOSE_WRITE | IN_CLOSE_NOWRITE;
const IN_OPEN = 0x00000020;
const IN_MOVED_FROM = 0x00000040;
const IN_MOVED_TO = 0x00000080;
const IN_MOVE = IN_MOVED_FROM | IN_MOVED_TO;
const IN_CREATE = 0x00000100;
const IN_DELETE = 0x00000200;
const IN_DELETE_SELF = 0x00000400;
const IN_MOVE_SELF = 0x00000800;

const Self = @This();
const EventsList = std.ArrayListUnmanaged(system.inotify_event);

allocator: Allocator,
epoll: fd_t,
inotify: fd_t,
events: EventsList,

pub fn init(allocator: Allocator) !Self {
    if (native_os == .windows) return error.NotSupported;

    const epoll = try posix.epoll_create1(0);
    errdefer posix.close(epoll);

    const inotify = try posix.inotify_init1(0);
    errdefer posix.close(inotify);

    return .{
        .allocator = allocator,
        .epoll = epoll,
        .inotify = inotify,
        .events = EventsList{},
    };
}

pub fn deinit(self: Self) void {
    posix.close(self.inotify);
    posix.close(self.epoll);
}

pub fn addDir(self: *Self, path: []const u8) !void {
    const wd = try posix.inotify_add_watch(self.inotify, path, IN_MODIFY | IN_CREATE | IN_DELETE); // add IN_MOVE??
    errdefer posix.inotify_rm_watch(self.inotify, wd);

    _ = try self.events.addOne(self.allocator);
}

pub fn start(self: *Self, callback: fn () void) !void {
    _ = callback;

    //var buf: [32]u8 = undefined;
    while (true) {
        // why tf it want me to read 32 bytes
        const bytes_read = try posix.read(self.inotify, mem.sliceAsBytes(self.events.items[0..]));
        const n = @divExact(bytes_read, @sizeOf(system.inotify_event));
        for (0..n) |i| {
            std.debug.print("read: {}\n", .{self.events.items[i]});
        }
    }
}
