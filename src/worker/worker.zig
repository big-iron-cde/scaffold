// worker.zig
// worker should be able to run tasks as docker containers, accept task runs from a manager,
// provide stats on task runs, and be able to keep track of its tasks and their state.

const std = @import("std");
const task = @import("task/task.zig");
const runTime = @import("runtime/runtime.zig");

/// worker is a struct that represents a worker node in the system.
pub const Worker = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    queue: std.AutoArrayHashMap(uuid.UUID, *task.Task),
    tasks: std.fifo.LinearFifo(*task.Task),
};
