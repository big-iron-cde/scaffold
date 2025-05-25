// worker.zig
// worker should be able to run tasks as docker containers, accept task runs from a manager,
// provide stats on task runs, and be able to keep track of its tasks and their state.

const std = @import("std");
const uuid = @import("uuid");
const task = @import("task/task.zig");
const docker = @import("docker");

pub const WorkerError = error{
    TaskNotFound,
    InvalidState,
    QueueFull,
    QueueEmpty,
    InvalidTaskState,
};

/// worker is a struct that represents a worker node in the system.
pub const Worker = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    queue: std.fifo.LinearFifo(*task.Task, .Dynamic),
    tasks: std.AutoArrayHashMap(uuid.UUID, *task.Task),
    docker_client: *docker.Client,

    // initialize the worker with an allocator and an id
    pub fn init(allocator: std.mem.Allocator) !Worker {
        var client = try docker.Client.init(allocator);
        errdefer client.deinit();

        return Worker{
            .allocator = allocator,
            .id = try std.fmt.allocPrint(allocator, "worker-{d}", .{std.crypto.random.int(u32)}),
            // initialize the queue with a hash map
            .queue = std.fifo.LinearFifo(*task.Task, .Dynamic).init(allocator),
            // initialize an empty task storage
            .tasks = std.AutoArrayHashMap(uuid.UUID, *task.Task).init(allocator),
            .docker_client = client,
        };
    }

    // task queue management
    pub fn enqueueTask(self: *Worker, t: *task.Task) !void {
        // TODO: should be able write the task to the end of the queue (?)
        // check if task is in valid state for queuing
        if (t.state != .pending and t.state != .scheduled) {
            return WorkerError.InvalidTaskState;
        }
        // add to FIFO queue
        try self.queue.writeItem(t);
        // then, store the task in the task map!
        try self.tasks.put(t.id, t);
        // debug statement
        std.debug.print("Enqueued task {s} (ID: {s})\n", .{ t.name, t.id });
    }

    // process the tasks in the queue
    pub fn processTasks(self: *Worker) !void {
        while (self.queue.readItem()) |t| {
            switch (t.state) {
                .scheduled => try self.startTask(t),
                .completed => try self.stopTask(t),
                else => return WorkerError.InvalidTaskState,
            }
        }
    }

    // start a task as a docker container
    pub fn startTask(self: *Worker, t: *task.Task) !void {
        // TODO: should be able to start a task
        // check if the task is invalid
        if (t.state != .pending and t.state != .scheduled) {
            // return an error
            return WorkerError.InvalidTaskState;
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
        // state machine
        try t.transition(.running);
        // debug print of the task name and ID
        std.debug.print("Running task {s} (ID: {s})\n", .{ t.name, t.id });
    }

    pub fn stopTask(self: *Worker, t: *task.Task) !void {
        // TODO: should be able to stop a task
        // first check if the task exists in our task list
        _ = self.tasks.get(t.id) orelse return WorkerError.TaskNotFound;
        // check if it is in running state
        if (t.state != .running) {
            return WorkerError.InvalidTaskState;
        }
        // transition the task to stopped
        try t.transition(.stopped);
        // remove the task from the task map
        try self.tasks.remove(t.id);
        // debug print
        std.debug.print("Stopping task {s} (ID: {s})\n", .{ t.name, t.id });
    }
};
