const std = @import("std");
const task = @import("../task/task.zig");
const worker = @import("../worker/worker.zig");
const scheduler = @import("../scheduler/scheduler.zig");

pub const ManagerError = error{
    WorkerNotFound,
    TaskNotFound,
    WorkerFull,
    InvalidTaskState,
    SchedulerError,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    pending_tasks: std.fifo.LinearFifo(*task.Task, .Dynamic),
    task_store: std.AutoHashMap(u128, *task.Task),
    workers: std.ArrayList(*worker.Worker),
    worker_task_map: std.StringHashMap(std.ArrayList(u128)),
    task_worker_map: std.AutoHashMap(u128, []const u8),
    scheduler: scheduler.Scheduler,
    task_counter: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, workers_list: []*worker.Worker) !*Manager {
        const manager = try allocator.create(Manager);

        manager.* = Manager{
            .allocator = allocator,
            .pending_tasks = std.fifo.LinearFifo(*task.Task, .Dynamic).init(allocator),
            .task_store = std.AutoHashMap(u128, *task.Task).init(allocator),
            .workers = std.ArrayList(*worker.Worker).init(allocator),
            .worker_task_map = std.StringHashMap(std.ArrayList(u128)).init(allocator),
            .task_worker_map = std.AutoHashMap(u128, []const u8).init(allocator),
            .scheduler = try scheduler.Scheduler.init(allocator, workers_list),
        };

        // add workers to manager's list
        try manager.workers.appendSlice(workers_list);

        // initialize worker-task mappings
        for (workers_list) |w| {
            try manager.worker_task_map.put(w.id, std.ArrayList(u128).init(allocator));
        }

        return manager;
    }

    pub fn deinit(self: *Manager) void {
        self.pending_tasks.deinit();

        // clean up task store
        var task_iter = self.task_store.iterator();
        while (task_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.task_store.deinit();

        // clean up worker-task mappings
        var wt_iter = self.worker_task_map.iterator();
        while (wt_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.worker_task_map.deinit();

        self.task_worker_map.deinit();
        self.workers.deinit();
        self.scheduler.deinit();
        self.allocator.destroy(self);
    }

    pub fn createTask(self: *Manager, name: []const u8, image: ?[]const u8, command: ?[][]const u8) !*task.Task {
        const t = try task.Task.init(self.allocator, name);
        self.task_counter += 1;

        if (image) |img| try t.setImage(img);
        if (command) |cmd| try t.setCommand(cmd);

        try self.task_store.put(t.ID, t);
        return t;
    }

    pub fn submitTask(self: *Manager, t: *task.Task) !void {
        try t.transition(.Pending);
        try self.pending_tasks.writeItem(t);
        std.log.info("Submitted task {s} (ID: {d})", .{ t.name, t.ID });
    }

    pub fn scheduleTasks(self: *Manager) !void {
        while (self.pending_tasks.readItem()) |t| {
            // Change 'worker' to 'selected_worker' to avoid shadowing the module import
            const selected_worker = try self.scheduler.schedule(self.allocator) catch return ManagerError.SchedulerError;

            if (t.state != .Pending and t.state != .Scheduled) {
                return ManagerError.InvalidTaskState;
            }

            try selected_worker.enqueueTask(t) catch return ManagerError.WorkerFull;
            try t.transition(.Scheduled);

            // Update task-worker mappings
            if (self.worker_task_map.getPtr(selected_worker.id)) |task_list| {
                try task_list.append(t.ID);
            }
            try self.task_worker_map.put(t.ID, selected_worker.id);

            std.log.info("Scheduled task {s} on worker {s}", .{ t.name, selected_worker.id });
        }
    }

    pub fn monitorTasks(self: *Manager) !void {
        for (self.workers.items) |w| {
            try w.processTasks();

            // check for completed tasks
            if (self.worker_task_map.get(w.id)) |task_ids| {
                var i: usize = 0;
                while (i < task_ids.items.len) {
                    const task_id = task_ids.items[i];
                    if (self.task_store.get(task_id)) |t| {
                        if (t.state == .Completed or t.state == .Failed or t.state == .Stopped) {
                            _ = task_ids.orderedRemove(i);
                            _ = self.task_worker_map.remove(task_id);
                            std.log.info("Task {s} completed with state {s}", .{ t.name, @tagName(t.state) });
                            continue;
                        }
                    }
                    i += 1;
                }
            }
        }
    }

    pub fn getTaskStatus(self: *Manager, task_id: u128) !task.State {
        const t = self.task_store.get(task_id) orelse return ManagerError.TaskNotFound;
        return t.state;
    }

    pub fn stopTask(self: *Manager, task_id: u128) !void {
        const t = self.task_store.get(task_id) orelse return ManagerError.TaskNotFound;
        const worker_id = self.task_worker_map.get(task_id) orelse return ManagerError.WorkerNotFound;

        for (self.workers.items) |w| {
            if (std.mem.eql(u8, w.id, worker_id)) {
                try w.stopTask(t);
                try t.transition(.Stopped);
                return;
            }
        }

        return ManagerError.WorkerNotFound;
    }

    pub fn getWorkerStats(self: *Manager) !std.ArrayList(struct {
        worker_id: []const u8,
        running_tasks: usize,
        pending_tasks: usize,
    }) {
        var stats = std.ArrayList(struct {
            worker_id: []const u8,
            running_tasks: usize,
            pending_tasks: usize,
        }).init(self.allocator);

        for (self.workers.items) |w| {
            const running = if (self.worker_task_map.get(w.id)) |ids| ids.items.len else 0;
            try stats.append(.{
                .worker_id = w.id,
                .running_tasks = running,
                .pending_tasks = w.queue.count,
            });
        }

        return stats;
    }
};
