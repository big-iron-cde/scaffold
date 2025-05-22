// worker.zig
// worker should be able to run tasks as docker containers, accept task runs from a manager,
// provide stats on task runs, and be able to keep track of its tasks and their state.

const std = @import("std");
const uuid = @import("uuid");
const task = @import("task/task.zig");
const runTime = @import("runtime/runtime.zig"); // this should be replaced w/ the docker prof is working w/

/// worker is a struct that represents a worker node in the system.
pub const Worker = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    queue: std.fifo.LinearFifo(*task.Task, .Dynamic),
    tasks: std.AutoArrayHashMap(uuid.UUID, *task.Task),

    // initialize the worker with an allocator and an id
    pub fn init(allocator: std.mem.Allocator) !Worker {
        return Worker{
            .allocator = allocator,
            .id = try std.fmt.allocPrint(allocator, "worker-{d}", .{std.crypto.random.int(u32)}),
            // initialize the queue with a hash map
            .queue = std.fifo.LinearFifo(*task.Task, .Dynamic).init(allocator),
            // initialize an empty task storage
            .tasks = std.AutoArrayHashMap(uuid.UUID, *task.Task).init(allocator),
        };
    }

    // task queue management
    pub fn enqueueTask(self: *Worker, t: *task.Task) !void {
        // TODO: should be able write the task to the end of the queue (?)
        // add to FIFO queue
        try self.queue.writeItem(t);
        // then, store the task in the task map!
        try self.tasks.put(t.id, t);
    }

    // processing tasks
    pub fn startTask(self: *Worker, t: *task.Task) !void {
        // TODO: should be able to start a task
        // check if the task is invalid
        if (t.state != .pending and t.state != .scheduled) {
            // return an erros
            return error.InvalidTaskState;
        }

        // transition the task to running
        try t.transition(.running);

        // add the task to the task map
        try self.tasks.put(t.id, t);

        // debug print of the task name and ID
        std.debug.print("Starting task {s} (ID: {s})\n", .{ t.name, t.id });

        // TODO: docker implementation
    }

    pub fn runTask(self: *Worker, t: *task.Task) !void {
        // TODO: should be able to run a task
        // be able to get the next task from the queue
        if (self.queue.readItem()) |t| {
            // state machine
            try t.transition(.running);
            // debug print of the task name and ID
            std.debug.print("Running task {s} (ID: {s})\n", .{ t.name, t.id });
        }
    }

    pub fn stopTask(self: *Worker, t: *task.Task) !void {
        // TODO: should be able to stop a task
    }
};
