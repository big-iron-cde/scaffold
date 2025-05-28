// scheduler.zig
// the scheduler should be able to determine a set of
// machines on which a task can run, score the candidate
// machines from the best to worst, and pick the machine
// with the highest score.

const std = @import("std");
const task = @import("../task/task.zig");
const worker = @import("../worker/worker.zig");

// made this is we ever need to add a new strategy
pub const SchedulerStrategy = enum { RoundRobin };

pub const Scheduler = struct {
    // Context contains scheduler state and dependencies
    const Context = struct {
        allocator: std.mem.Allocator,
        workers: []*worker.Worker,
        current_index: usize = 0,
        strategy: SchedulerStrategy = .RoundRobin,
    };

    ptr: *Context,

    // initialize a new scheduler
    pub fn init(allocator: std.mem.Allocator, workers: []*worker.Worker) !Scheduler {
        const ctx = try allocator.create(Context);
        ctx.* = .{
            .allocator = allocator,
            .workers = workers,
            .current_index = 0,
            .strategy = .RoundRobin,
        };
        return Scheduler{ .ptr = ctx };
    }

    pub fn deinit(self: *Scheduler) void {
        self.ptr.allocator.destroy(self.ptr);
    }

    // step 1: select candidate nodes (for round-robin, we just return all workers)
    pub fn selectCandidateNodes(self: *Scheduler) []*worker.Worker {
        return self.ptr.workers;
    }

    // step 2: score the candidate nodes (round-robin assigns 0.1 to next worker, 1.0 to others)
    pub fn score(self: *Scheduler, allocator: std.mem.Allocator, candidates: []*worker.Worker) !std.StringHashMap(f32) {
        var scores = std.StringHashMap(f32).init(allocator);
        errdefer scores.deinit();

        for (candidates) |w| {
            const candidate_score: f32 = if (self.ptr.current_index < candidates.len and
                std.mem.eql(u8, w.id, candidates[self.ptr.current_index].id))
                0.1
            else
                1.0;

            try scores.put(w.id, candidate_score);
        }

        return scores;
    }

    // step 3: select the best node (round-robin just returns the lowest score)
    pub fn pick(self: *Scheduler, scores: *std.StringHashMap(f32)) !*worker.Worker {
        var best_score: f32 = std.math.f32_max;
        var best_worker: ?*worker.Worker = null;

        var it = scores.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* < best_score) {
                best_score = entry.value_ptr.*;
                // find the worker with this id
                for (self.ptr.workers) |w| {
                    if (std.mem.eql(u8, w.id, entry.key_ptr.*)) {
                        best_worker = w;
                        break;
                    }
                }
            }
        }

        // update the round-robin index for the next time
        if (best_worker) |w| {
            for (self.ptr.workers, 0..) |worker_ptr, i| {
                if (std.mem.eql(u8, worker_ptr.id, w.id)) {
                    self.ptr.current_index = (i + 1) % self.ptr.workers.len;
                    break;
                }
            }
            return w;
        }

        return error.NoWorkerAvailable;
    }

    // method that runs all the steps of the scheduler
    pub fn schedule(self: *Scheduler, allocator: std.mem.Allocator) !*worker.Worker {
        const candidates = self.selectCandidateNodes();
        var scores = try self.score(allocator, candidates);
        defer scores.deinit();
        return try self.pick(&scores);
    }
};
