// scheduler.zig
// the scheduler ishould be able to determine a set of
// machines on which a task can run. score the candidate
// machines from the best to worst, and pick the machine
// with the highest score.

const std = @import("std");
const task = @import("../task/task.zig");
const node = @import("node.zig"); // assume this is already here

pub const Scheduler = struct {
    // interface methods
    pub const Interface = struct {
        selectCandidateNodes: *const fn (allocator: std.mem.Allocator, task: *task.Task, nodes: []*node.Node) []*node.Node,

        score: *const fn (allocator: std.mem.Allocator, task: *task.Task, nodes: []*node.Node) std.StringHashMap(f32),

        pick: *const fn (scores: std.StringHashMap(f32), candidates: []*node.Node) ?*node.Node,
    };
};
