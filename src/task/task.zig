const State = enum(u8) {
    Pending,
    Scheduled,
    Completed,
    Running,
    Failed
};

const Task = struct {
    ID: uuid.v4.new(),
    name: []const u8,
    state: State,
};

const std = @import("std");
const uuid = @import("uuid");
