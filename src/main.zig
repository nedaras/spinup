const std = @import("std");
const fs = std.fs;
const path = fs.path;
const json = std.json;
const mem = std.mem;
const Watcher = @import("Watcher.zig");

pub fn executeCommand(allocator: std.mem.Allocator, command: []const []const u8) !void {
    var child = std.ChildProcess.init(command, allocator);
    _ = try child.spawnAndWait();
}

pub fn callback(watcher: *Watcher, absolute_path: []const u8, event: Watcher.Event) void {
    if (!event.is_dir) {
        executeCommand(watcher.allocator, &.{ "echo", "hello world!!!" }) catch |err| {
            std.debug.print("Could not run command, returned with error: {}\n", .{err});
        };
    }
    if (event.is_dir and event.type == .create) {
        // TODO: we sould handle errors.
        watcher.addDir(absolute_path) catch unreachable;
    }
}

const JSONConfig = struct {
    include: []const []const u8,
    exclude: []const []const u8,
    run: []const []const u8,
};

const Config = struct {
    pub fn init(config: JSONConfig) Config {
        _ = config;
        return .{};
    }

    pub fn isWatched(self: Config, _path: []const u8) !bool {
        _ = self;
        var it = try path.componentIterator(_path);
        while (it.next()) |component| {
            std.debug.print("sub: {s}\n", .{component.name});
        }
        return false;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const file = try fs.cwd().openFile("spinup.config.json", .{});
    defer file.close();

    var reader = json.reader(allocator, file.reader().any()); // use br
    defer reader.deinit();

    const parsed = try json.parseFromTokenSource(JSONConfig, allocator, &reader, .{});
    defer parsed.deinit();

    const config = Config.init(parsed.value);
    // soo this means that path has to end with /src...
    // but what if a/**/c/*.ts
    // or
    // but what if a/*/c/*.ts
    _ = try config.isWatched("**/src/a/b/cc/index.d.ts");

    std.debug.print("{}\n", .{parsed.value});

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

fn isMatch(match: []const u8, in: []const u8) bool {
    var match_it = try path.componentIterator(match);
    var in_it = try path.componentIterator(in);

    var atleast: u32 = 0;
    main: while (match_it.next()) |entry| {
        if (mem.eql(u8, entry.name, "**")) {
            atleast += 1;
        } else if (mem.containsAtLeast(u8, entry.name, 1, "*")) {
            if (entry.name.len == 1) {
                atleast += 1;
            } else {
                // prob we will loop till atleast and do simular match function like this just simpler
                std.debug.print("idk how to handle", .{});
            }
        } else {
            const target = entry.name;
            for (0..atleast) |_| {
                if (in_it.next() == null) return false;
            }

            while (in_it.next()) |e2| {
                if (mem.eql(u8, target, e2.name)) {
                    atleast = 0;
                    continue :main;
                }
            }
            return false;
        }
    }

    for (0..atleast) |_| {
        if (in_it.next() == null) return false;
    }
    return true;
}

test "wildchar characters" {
    try std.testing.expect(isMatch("src/**/*/src/**/*", "src/a/b/d/g/src/a/a/a/a"));
    try std.testing.expect(isMatch("src/*/*/src/**/*", "src/d/g/src/a/a/a/a"));
    try std.testing.expect(!isMatch("src/*/*/src/**/*/dist", "src/d/g/src/a/a/a/a"));
    try std.testing.expect(!isMatch("**/*/hell", "a/hell"));
    try std.testing.expect(isMatch("**/*/hell", "a/a/hell"));
    try std.testing.expect(!isMatch("**/*/hell/**", "a/a/hell"));
    try std.testing.expect(!isMatch("**/*/hell/**/**", "a/a/hell"));
    try std.testing.expect(!isMatch("**/*/hell/**/**", "a/a/hell/hell"));
    try std.testing.expect(isMatch("**/*/hell/**", "a/a/hell/a"));
    try std.testing.expect(isMatch("**/*/hell/**", "a/a/hell/a/bbbf/dd"));
    try std.testing.expect(isMatch("**/*/hell/**", "hello/world/a/a/hell/a/bbbf/dd"));
    try std.testing.expect(isMatch("src/*/*/src/**/config.*.json", "src/d/g/src/a/a/a/config.hello.json"));
    try std.testing.expect(isMatch("src/*/*/src/**/*ed/config.*.json", "src/d/g/src/a/a/folder/config.hello.json"));
}
