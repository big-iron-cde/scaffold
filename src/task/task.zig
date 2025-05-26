const State = enum(u8) { Pending, Scheduled, Completed, Running, Failed, Stopped };

pub const Task = struct {
    ID: []const u8,
    name: []const u8,
    state: State,
    allocator: std.mem.Allocator,

    // docker specific config
    // docker image to use
    image: ?[]const u8 = null,
    // the docker container ID
    container_id: ?[]const u8 = null,
    // env variables
    env: ?[][]const u8 = null,
    // the exit code of the task
    exit_code: i32 = 0,
    error_message: ?[]const u8 = null,
    command: ?[][]const u8 = null,

    // initialize a new task with the given name
    pub fn init(allocator: std.mem.Allocator, name: []const u8) !*Task {
        const id = try uuid.v4.new(allocator);
        const task = try allocator.create(Task);

        task.* = Task{
            .allocator = allocator,
            .ID = id,
            .name = try allocator.dupe(u8, name),
            .state = .Pending,
            .image = null,
            .container_id = null,
            .env = null,
            .exit_code = 0,
            .error_message = null,
            .command = null,
        };

        return task;
    }

    // clean up all the task resources
    pub fn deinit(self: *Task) void {
        self.allocator.free(self.ID);
        self.allocator.free(self.name);

        if (self.image) |image| {
            self.allocator.free(image);
        }
        if (self.container_id) |container_id| {
            self.allocator.free(container_id);
        }

        if (self.command) |cmd| {
            for (cmd) |arg| {
                self.allocator.free(arg);
            }
            self.allocator.free(cmd);
        }

        if (self.env) |env_vars| {
            for (env_vars) |env| {
                self.allocator.free(env);
            }
            self.allocator.free(env);
        }

        self.allocator.destroy(self);
    }

    // transition function to transition the task to a new state
    pub fn transition(self: *Task, new_state: State) !void {
        // validate the state transition
        switch (self.state) {
            .Pending => {
                if (new_state != .Scheduled and new_state != .Running) {
                    return error.InvalidStateTransition;
                }
            },
            .Scheduled => {
                if (new_state != .Running) {
                    return error.InvalidStateTransition;
                }
            },
            .Running => {
                if (new_state != .Completed and new_state != .Failed and new_state != .Stopped) {
                    return error.InvalidStateTransition;
                }
            },
            else => {},
        }
        self.state = new_state;
    }

    // set the docker image for this container
    pub fn setImage(self: *Task, image: []const u8) !void {
        if (self.image) |old_image| {
            self.allocator.free(old_image);
        }
        self.image = try self.allocator.dupe(u8, image);
    }

    // set the command to run in the container
    pub fn setCommand(self: *Task, command: []const []const u8) !void {
        if (self.command) |cmd| {
            for (cmd) |arg| {
                self.allocator.free(arg);
            }
            self.allocator.free(cmd);
        }
        const new_cmd = try self.allocator.alloc([]const u8, command.len);
        for (command, 0..) |arg, i| {
            new_cmd[i] = try self.allocator.dupe(u8, arg);
        }
        self.command = new_cmd;
    }

    pub fn addEnv(self: *Task, env_var: []const u8) !void {
        const new_env = if (self.env) |existing| blk: {
            const res = try self.allocator.realloc(existing, existing.len + 1);
            res[existing.len] = try self.allocator.dupe(u8, env_var);
            break :blk res;
        } else blk: {
            const res = try self.allocator.alloc([]const u8, 1);
            res[0] = try self.allocator.dupe(u8, env_var);
            break :blk res;
        };
        self.env = new_env;
    }

    /// record the task's completion status
    pub fn recordCompletion(self: *Task, exit_code: i32, error_msg: ?[]const u8) !void {
        self.exit_code = exit_code;
        if (error_msg) |msg| {
            if (self.error_message) |existing| {
                self.allocator.free(existing);
            }
            self.error_message = try self.allocator.dupe(u8, msg);
        }

        try self.transition(if (exit_code == 0) .Completed else .Failed);
    }
};

const std = @import("std");
const uuid = @import("uuid");
