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
const fs = std.fs;
const assert = std.debug.assert;
const fmt = std.fmt;

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
wd_paths: std.AutoHashMapUnmanaged(i32, []const u8),

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
        .wd_paths = std.AutoHashMapUnmanaged(i32, []const u8){},
    };
}

pub fn deinit(self: *Self) void {
    posix.close(self.inotify);
    posix.close(self.epoll);
    self.events.deinit(self.allocator);
    self.wd_paths.deinit(self.allocator);
}

pub fn addDir(self: *Self, path: []const u8) !void {
    const wd = try posix.inotify_add_watch(self.inotify, path, IN_MODIFY | IN_CREATE | IN_DELETE); // add IN_MOVE??
    errdefer posix.inotify_rm_watch(self.inotify, wd);

    _ = try self.events.addOne(self.allocator);
    errdefer _ = self.events.pop();

    try self.wd_paths.put(self.allocator, wd, path);
}

inline fn getAbsolutePath(dir: []const u8, file: []const u8) []const u8 {
    assert(!fs.path.isSep(dir[dir.len - 1]));
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    return fmt.bufPrint(&buf, "{s}/{s}", .{ dir, file }) catch unreachable;
}

fn getEventFromMask(mask: u32) ?EventType {
    if (mask & IN_MODIFY != 0) return .modify;
    if (mask & IN_CREATE != 0) return .create;
    if (mask & IN_DELETE != 0) return .delete;
    if (mask & IN_MOVE != 0) return .move;
    return null;
}

pub const Event = struct {
    is_dir: bool,
    type: EventType,
};

const EventType = enum {
    modify,
    create,
    delete,
    move,
};

pub fn run(self: *Self, callback: fn (absolute_path: []const u8, event: Event) void) !void {
    var buf: [@sizeOf(system.inotify_event) + fs.MAX_NAME_BYTES + 1]u8 align(4) = undefined;
    while (true) {
        const bytes_read = try posix.read(self.inotify, &buf);
        var start = @intFromPtr(&buf);
        const end = @intFromPtr(&buf) + bytes_read;

        while (start != end) {
            const event = mem.bytesAsValue(system.inotify_event, @as(*[:0]u8, @ptrFromInt(start)));
            const event_size = @sizeOf(system.inotify_event) + event.len;
            defer start += event_size;
            if (event.getName()) |name| {
                assert(self.wd_paths.contains(event.wd));
                const path = self.wd_paths.getPtr(event.wd).?;
                const event_type = getEventFromMask(event.mask).?;

                callback(getAbsolutePath(path.*, name), .{ .is_dir = event.mask & IN_ISDIR != 0, .type = event_type });
            }
        }
    }
}
