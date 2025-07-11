// worker.zig
// worker should be able to run tasks as docker containers, accept task runs from a manager,
// provide stats on task runs, and be able to keep track of its tasks and their state.

const std = @import("std");
const uuid = @import("uuid");
const task = @import("../task/task.zig");
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
    tasks: std.AutoArrayHashMap(u128, *task.Task),

    // initialize the worker with an allocator and an id
    pub fn init(allocator: std.mem.Allocator) !Worker {
        return Worker{
            .allocator = allocator,
            .id = try std.fmt.allocPrint(allocator, "worker-{d}", .{std.crypto.random.int(u32)}),
            // initialize the queue with a hash map
            .queue = std.fifo.LinearFifo(*task.Task, .Dynamic).init(allocator),
            // initialize an empty task storage
            .tasks = std.AutoArrayHashMap(u128, *task.Task).init(allocator),
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
        if (t.state != .Pending and t.state != .Scheduled) {
            return WorkerError.InvalidTaskState;
        }
        // add to FIFO queue
        try self.queue.writeItem(t);
        // then, store the task in the task map!
        try self.tasks.put(t.ID, t);
        // debug statement
        std.debug.print("Enqueued task {s} (ID: {any})\n", .{ t.name, t.ID });
    }

    // process the tasks in the queue
    pub fn processTasks(self: *Worker) !void {
        while (self.queue.readItem()) |t| {
            switch (t.state) {
                .Scheduled => try self.startTask(t),
                .Completed => {
                    // remove the completed tasks from tracking
                    _ = self.tasks.remove(t.ID);
                },
                else => return WorkerError.InvalidTaskState,
            }
        }
    }

    // start a task as a docker container
    pub fn startTask(self: *Worker, t: *task.Task) !void {
        // TODO: should be able to start a task
        // check if the task is invalid
        if (t.state != .Pending and t.state != .Scheduled) {
            // return an error
            return WorkerError.InvalidTaskState;
        }

        // transition the task to running
        try t.transition(.Running);

        // add the task to the task map
        try self.tasks.put(t.ID, t);

        // debug print of the task name and ID
        std.debug.print("Starting task {s} (ID: {any})\n", .{ t.name, uuid.urn.serialize(t.ID) });

        // TODO: docker implementation
        // docker container creation and start
        try self.createContainer(t);
        try self.startContainer(t);
        std.time.sleep(1 * std.time.ns_per_s); // for 1 second
    }

    // create a docker container for the task
    fn createContainer(self: *Worker, t: *task.Task) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        // add bind mounts for workspace persistence
        const home_dir = std.posix.getenv("HOME") orelse "/tmp";
        const workspace_path = try std.fmt.allocPrint(alloc, "{s}/scaffold-workspace-{s}", .{ home_dir, &uuid.urn.serialize(t.ID) });

        // create workspace directory
        std.fs.makeDirAbsolute(workspace_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const bind_mount = try std.fmt.allocPrint(alloc, "{s}:/workspace:rw", .{workspace_path});

        // create an empty PortMap struct (since PortMap is just an empty struct in the old API)
        const port_map = docker.PortMap{};

        const host_config = docker.HostConfig{
            .AutoRemove = true,
            .PortBindings = port_map,
            .Binds = &[_]?[]const u8{bind_mount},
        };

        const networking_config = docker.NetworkingConfig{};
        const container_name = uuid.urn.serialize(t.ID);

        const create_response = try docker.@"/containers/create".post(alloc, .{
            .name = &container_name,
        }, .{
            .body = .{
                .Image = t.image orelse {
                    std.log.err("Task {s} has no image specified", .{t.name});
                    return WorkerError.DockerError;
                },
                .Cmd = t.command orelse &[_][]const u8{},
                .Env = t.env orelse &[_][]const u8{},
                .AttachStdout = true,
                .AttachStderr = true,
                .HostConfig = host_config,
                .NetworkingConfig = networking_config,
            },
        });

        switch (create_response) {
            .@"201" => |container| {
                t.container_id = try self.allocator.dupe(u8, container.Id);
                t.workspace_path = try self.allocator.dupe(u8, workspace_path);
                std.log.info("Created container {s} with workspace {s}", .{ container.Id, workspace_path });
            },
            else => {
                std.log.err("Failed to create container for task {s}: {any}", .{ t.name, create_response });
                return WorkerError.DockerError;
            },
        }
    }

    fn startContainer(self: *Worker, t: *task.Task) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        if (t.container_id) |container_id| {
            const start_response = try docker.@"/containers/{id}/start".post(alloc, .{
                .id = container_id,
            }, .{ .detachKeys = "" });

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
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const stop_response = try docker.@"/containers/{id}/stop".post(alloc, .{
            .id = container_id,
        }, .{ .signal = "", .t = 0 });

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
        try t.transition(.Running);
        // debug print of the task name and ID
        std.debug.print("Running task {s} (ID: {s})\n", .{ t.name, &uuid.urn.serialize(t.ID) });

        // if it's a container task, start it
        if (t.image) |_| {
            try self.startTask(t);
        }
    }

    pub fn stopTask(self: *Worker, t: *task.Task) !void {
        // TODO: should be able to stop a task
        // first check if the task exists in our task list
        _ = self.tasks.get(t.ID) orelse return WorkerError.TaskNotFound;
        // check if it is in running state
        if (t.state != .Running) {
            return WorkerError.InvalidTaskState;
        }
        // transition the task to stopped
        try t.transition(.Stopped);

        // stop the container if it exists
        if (t.container_id) |container_id| {
            try self.stopContainer(container_id);
        }

        // remove the task from the task map
        _ = self.tasks.swapRemove(t.ID);
        // debug print
        std.debug.print("Stopping task {s} (ID: {s})\n", .{ t.name, &uuid.urn.serialize(t.ID) });
    }
};
