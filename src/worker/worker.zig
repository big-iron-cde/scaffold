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
    DockerError,
};

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

    pub fn deinit(self: *Worker) void {
        self.allocator.free(self.id);
        self.queue.deinit();

        var task_iter = self.tasks.iterator();
        while (task_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.tasks.deinit();
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
        // docker container creation and start
        try self.createContainer(t);
        try self.startContainer(t);
    }

    // create a docker container for the task
    fn createContainer(self: *Worker, t: *task.Task) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const alloc = gpa.allocator();

        const container_config = docker.ContainerConfig{
            .Image = t.image orelse {
                std.log.err("Task {s} has no image specified", .{t.name});
                return WorkerError.DockerError;
            },
            .Cmd = t.command orelse &[_][]const u8{},
            .Env = t.env orelse &[_][]const u8{},
            .Labels = .{
                ."task_id" = t.id,
                ."task_name" = t.name,
            },
            .HostConfig = docker.HostConfig{
                .AutoRemove = true,
            },
        };

        const container_name = try std.fmt.allocPrint(alloc, "task_{s}", .{t.id[0..8]});
        defer alloc.free(container_name);

        const create_response = try docker.@"/containers/create".post(alloc, .{
            .name = container_name,
            .body = container_config,
        });

        switch (create_response) {
            .@"201" => |container| {
                t.container_id = try self.allocator.dupe(u8, container.Id);
            },
            else => {
                std.log.err("Failed to create container for task {s}: {any}", .{ t.name, create_response });
                return WorkerError.DockerError;
            },
        }
    }

    fn startContainer(self: *Worker, t: *task.Task) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const alloc = gpa.allocator();

        if (t.container_id) |container_id| {
            const start_response = try docker.@"/containers/{id}/start".post(alloc, .{
                .id = container_id,
            });

            switch (start_response) {
                // success!
                .@"204" => {},
                // container already started
                .@"304" => {},
                else => {
                    std.log.err("Failed to start container for task {s}: {any}", .{ t.name, start_response });
                    return WorkerError.DockerError;
                },
            }
        } else {
            std.log.err("Task {s} has no container ID", .{t.name});
            return WorkerError.DockerError;
        }
    }

    fn stopContainer(self: *Worker, container_id: []const u8) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const alloc = gpa.allocator();

        const stop_response = try docker.@"/containers/{id}/stop".post(alloc, .{
            .id = container_id,
        });

        switch (stop_response) {
            // success!
            .@"204" => {},
            // container already stopped
            .@"304" => {},
            else => {
                std.log.err("Failed to stop container {s}: {any}", .{ container_id, stop_response });
                return WorkerError.DockerError;
            },
        }
    }

    pub fn runTask(self: *Worker, t: *task.Task) !void {
        // TODO: should be able to run a task
        // state machine
        try t.transition(.running);
        // debug print of the task name and ID
        std.debug.print("Running task {s} (ID: {s})\n", .{ t.name, t.id });
        
        // if it's a container task, start it
        if (t.image) |_| {
            try self.startTask(t);
        }
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
        
        // stop the container if it exists
        if (t.container_id) |container_id| {
            try self.stopContainer(container_id);
        }
        
        // remove the task from the task map
        _ = self.tasks.remove(t.id);
        // debug print
        std.debug.print("Stopping task {s} (ID: {s})\n", .{ t.name, t.id });
    }
};