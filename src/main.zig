pub fn main() !void {
    var server = try listener.initZincServer();

    try server.run();
}

const std = @import("std");
const listener = @import("listener/listener.zig");
const task = @import("task/task.zig");
