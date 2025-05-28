const std = @import("std");
const worker = @import("src/worker/worker.zig");
const task = @import("src/task/task.zig");
const scheduler = @import("src/scheduler/scheduler.zig");

test "create worker" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var w = try worker.Worker.init(alloc);
    defer w.deinit();

    std.log.info("Worker ID: {s}", .{w.id});
    std.log.info("Tasks count: {d}", .{w.tasks.count()});
    std.log.info("Queue count: {d}", .{w.queue.count});
}

test "enqueue task" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var w = try worker.Worker.init(alloc);
    defer w.deinit();

    const t = try task.Task.init(alloc, "test-task");
    // TODO: Deinitializing the task here creates a SEGFAULT!
    //defer t.deinit();

    try w.enqueueTask(t);

    std.log.info("Task ID: {d}", .{t.ID});
    std.log.info("Task state: {s}", .{@tagName(t.state)});
    std.log.info("Tasks in worker: {d}", .{w.tasks.count()});
}

test "dequeue task" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var w = try worker.Worker.init(alloc);
    defer w.deinit();

    const t = try task.Task.init(alloc, "test-task");
    try w.enqueueTask(t);

    // verify if task is in queue
    try std.testing.expectEqual(@as(usize, 1), w.queue.count);
    try std.testing.expectEqual(@as(usize, 1), w.tasks.count());

    // dequeue the task
    if (w.queue.readItem()) |dequeued_task| {
        try std.testing.expectEqual(t.ID, dequeued_task.ID);
        try std.testing.expectEqual(@as(usize, 0), w.queue.count);
        // task should still be in the tasks map
        try std.testing.expectEqual(@as(usize, 1), w.tasks.count());
    } else {
        return error.TestFailure;
    }
}

test "task state transitions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var w = try worker.Worker.init(alloc);
    defer w.deinit();

    const t = try task.Task.init(alloc, "transition-task");
    try std.testing.expectEqual(task.State.Pending, t.state);

    // testc valid transitions
    try t.transition(.Scheduled);
    try std.testing.expectEqual(task.State.Scheduled, t.state);

    try w.enqueueTask(t);

    // test invalid transition - should return error
    const result = t.transition(.Pending);
    try std.testing.expectError(error.InvalidStateTransition, result);
}

test "initialize scheduler" {
    std.log.info("Running initialize scheduler test", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // Create some workers
    var worker1 = try worker.Worker.init(alloc);
    defer worker1.deinit();
    var worker2 = try worker.Worker.init(alloc);
    defer worker2.deinit();

    // Create an array of worker pointers
    var workers = [_]*worker.Worker{ &worker1, &worker2 };

    // Initialize scheduler
    var sched = try scheduler.Scheduler.init(alloc, &workers);
    defer sched.deinit();

    // Verify scheduler has the correct workers
    try std.testing.expectEqual(@as(usize, 2), sched.ptr.workers.len);
    try std.testing.expectEqual(worker1.id, sched.ptr.workers[0].id);
    try std.testing.expectEqual(worker2.id, sched.ptr.workers[1].id);
    std.log.info("Scheduler initialized with workers: {s} and {s}", .{ worker1.id, worker2.id });
}

test "select candidate nodes" {
    std.log.warn("\n===== TESTING SELECT CANDIDATE NODES =====\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // create some workers
    var worker1 = try worker.Worker.init(alloc);
    defer worker1.deinit();
    var worker2 = try worker.Worker.init(alloc);
    defer worker2.deinit();
    var worker3 = try worker.Worker.init(alloc);
    defer worker3.deinit();

    // create an array of worker pointers
    var workers = [_]*worker.Worker{ &worker1, &worker2, &worker3 };

    // initialize scheduler
    var sched = try scheduler.Scheduler.init(alloc, &workers);
    defer sched.deinit();

    // test the candidate selection
    const candidates = sched.selectCandidateNodes();
    // should expect 3 candidates!
    try std.testing.expectEqual(@as(usize, 3), candidates.len);
    try std.testing.expectEqual(worker1.id, candidates[0].id);
    try std.testing.expectEqual(worker2.id, candidates[1].id);
    try std.testing.expectEqual(worker3.id, candidates[2].id);

    std.log.warn("Selected all {d} candidates as expected\n", .{candidates.len});
}

test "score candidates" {
    std.log.warn("\n===== TESTING SCORE CANDIDATES WITH THREE WORKERS =====\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // create some workers
    var worker1 = try worker.Worker.init(alloc);
    defer worker1.deinit();
    var worker2 = try worker.Worker.init(alloc);
    defer worker2.deinit();
    var worker3 = try worker.Worker.init(alloc);
    defer worker3.deinit();

    // create an array of worker pointers
    var workers = [_]*worker.Worker{ &worker1, &worker2, &worker3 };

    // initialize scheduler
    var sched = try scheduler.Scheduler.init(alloc, &workers);
    defer sched.deinit();

    // test scoring
    var scores = try sched.score(alloc, &workers);
    defer scores.deinit();

    // the first worker should have a score of 0.1 (round-robin starts at index 0)
    try std.testing.expectEqual(@as(f32, 0.1), scores.get(worker1.id).?);
    // second worker should have a score of 1.0
    try std.testing.expectEqual(@as(f32, 1.0), scores.get(worker2.id).?);
    // third worker should also have a score of 1.0
    try std.testing.expectEqual(@as(f32, 1.0), scores.get(worker3.id).?);

    std.log.warn("Worker scores: {s}={d}, {s}={d}, {s}={d}\n", .{ worker1.id, scores.get(worker1.id).?, worker2.id, scores.get(worker2.id).?, worker3.id, scores.get(worker3.id).? });
}
