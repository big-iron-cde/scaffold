pub fn main() !void {
    var server = listener.initZincServer();
    server.runServer();
}

const std = @import("std");
const listener = @import("listener/listener.zig");
const task = @import("task/task.zig");
