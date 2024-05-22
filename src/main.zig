const std = @import("std");
const fs = std.fs;
const path = fs.path;
const Watcher = @import("Watcher.zig");

pub fn callback(watcher: *Watcher, absolute_path: []const u8, event: Watcher.Event) void {
    const suffix = if (event.is_dir) "dir" else "file";
    std.debug.print("path_update: {s}({s}) ({})\n", .{ absolute_path, suffix, event.type });

    if (event.is_dir and event.type == .delete) {
        watcher.removeDir(path.dirname(absolute_path).?) catch std.debug.panic("...");
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!

    var watcher = try Watcher.init(allocator);
    defer watcher.deinit();

    // TODO: we need to add like 1 second delay in callback to know when to reload
    try watcher.addDir("src");
    try watcher.run(callback);
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
