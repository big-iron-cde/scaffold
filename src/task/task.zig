const std = @import("std");
const uuid = @import("uuid");

pub const State = enum(u8) { Pending, Scheduled, Completed, Running, Failed, Stopped };

pub const Task = struct {
    allocator: std.mem.Allocator,
    ID: u128,
    name: []const u8,
    state: State,
    image: ?[]const u8,
    // docker specific config
    // docker image to use
    command: ?[]const []const u8,
    env: ?[]const []const u8,
    container_id: ?[]const u8,
    workspace_path: ?[]const u8,
    exit_code: i32,
    error_message: ?[]const u8,

    // initialize a new task with the given name
    pub fn init(allocator: std.mem.Allocator, name: []const u8) !*Task {
        const id = uuid.v4.new();
        const task = try allocator.create(Task);

        task.* = Task{
            .allocator = allocator,
            .ID = id,
            .name = try allocator.dupe(u8, name),
            .state = .Pending,
            .image = null,
            .container_id = null,
            .env = null,
            .command = null,
            .workspace_path = null,
            .exit_code = 0, // Now this field exists
            .error_message = null, // Now this field exists
        };

        return task;
    }

    // clean up all the task resources
    pub fn deinit(self: *Task) void {
        self.allocator.free(self.name);
        if (self.image) |img| self.allocator.free(img);
        if (self.container_id) |id| self.allocator.free(id);
        if (self.workspace_path) |path| self.allocator.free(path);
        if (self.error_message) |msg| self.allocator.free(msg); // Clean up error message

        if (self.command) |cmd| {
            for (cmd) |arg| self.allocator.free(arg);
            self.allocator.free(cmd);
        }

        if (self.env) |environment| {
            for (environment) |env_var| self.allocator.free(env_var);
            self.allocator.free(environment);
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
