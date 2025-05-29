const std = @import("std");
const worker = @import("src/worker/worker.zig");
const task = @import("src/task/task.zig");
const scheduler = @import("src/scheduler/scheduler.zig");

test "create worker" {
    std.log.warn("\n===== TESTING CREATE WORKER =====\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var w = try worker.Worker.init(alloc);
    defer w.deinit();

    std.log.warn("Worker created: ID={s}, Tasks={d}, Queue={d}\n", .{ w.id, w.tasks.count(), w.queue.count });
}

test "enqueue task" {
    std.log.warn("\n===== TESTING ENQUEUE TASK =====\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var w = try worker.Worker.init(alloc);
    defer w.deinit();

    const t = try task.Task.init(alloc, "test-task");
    // TODO: Deinitializing the task here creates a SEGFAULT!
    //defer t.deinit();

    try w.enqueueTask(t);

    std.log.warn("Task enqueued: ID={d}, State={s}, Worker tasks={d}\n", .{ t.ID, @tagName(t.state), w.tasks.count() });
}

test "dequeue task" {
    std.log.warn("\n===== TESTING DEQUEUE TASK =====\n", .{});
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

        std.log.warn("Task dequeued: ID={d}, Queue count={d}, Tasks map count={d}\n", .{ dequeued_task.ID, w.queue.count, w.tasks.count() });
    } else {
        return error.TestFailure;
    }
}

test "task state transitions" {
    std.log.warn("\n===== TESTING TASK STATE TRANSITIONS =====\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var w = try worker.Worker.init(alloc);
    defer w.deinit();

    const t = try task.Task.init(alloc, "transition-task");
    try std.testing.expectEqual(task.State.Pending, t.state);

    // test valid transitions
    try t.transition(.Scheduled);
    try std.testing.expectEqual(task.State.Scheduled, t.state);

    try w.enqueueTask(t);

    // test invalid transition - should return error
    const result = t.transition(.Pending);
    try std.testing.expectError(error.InvalidStateTransition, result);

    std.log.warn("Task transitions: Initial=Pending, Current={s}, Invalid transition caught={}\n", .{ @tagName(t.state), @errorReturnTrace() != null });
}

test "initialize scheduler" {
    std.log.warn("\n===== TESTING INITIALIZE SCHEDULER =====\n", .{});
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

    std.log.warn("Scheduler initialized with workers: {s} and {s}\n", .{ worker1.id, worker2.id });
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

// add the pick best worker test
test "pick best worker" {
    std.log.warn("\n===== TESTING PICK BEST WORKER =====\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // create some workers
    var worker1 = try worker.Worker.init(alloc);
    defer worker1.deinit();
    var worker2 = try worker.Worker.init(alloc);
    defer worker2.deinit();

    // create an array of worker pointers
    var workers = [_]*worker.Worker{ &worker1, &worker2 };

    // initialize scheduler
    var sched = try scheduler.Scheduler.init(alloc, &workers);
    defer sched.deinit();

    // create scores
    var scores = std.StringHashMap(f32).init(alloc);
    defer scores.deinit();
    try scores.put(worker1.id, 0.5);
    try scores.put(worker2.id, 0.1); // Worker2 has better score

    // test picking
    const best_worker = try sched.pick(&scores);
    try std.testing.expectEqual(worker2.id, best_worker.id);

    std.log.warn("Scores: {s}={d}, {s}={d}, Picked best worker: {s}\n", .{ worker1.id, scores.get(worker1.id).?, worker2.id, scores.get(worker2.id).?, best_worker.id });
}

test "round robin scheduling" {
    std.log.warn("\n===== TESTING ROUND ROBIN SCHEDULING =====\n", .{});
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

    // first schedule call should pick worker1
    const first = try sched.schedule(alloc);
    try std.testing.expectEqual(worker1.id, first.id);

    // second schedule call should pick worker2
    const second = try sched.schedule(alloc);
    try std.testing.expectEqual(worker2.id, second.id);

    // third schedule call should pick worker3
    const third = try sched.schedule(alloc);
    try std.testing.expectEqual(worker3.id, third.id);

    // fourth schedule call should cycle back to worker1
    const fourth = try sched.schedule(alloc);
    try std.testing.expectEqual(worker1.id, fourth.id);

    std.log.warn("Round robin order: 1st={s}, 2nd={s}, 3rd={s}, 4th={s}\n", .{ first.id, second.id, third.id, fourth.id });
}

test "scheduler integration tests" {
    std.log.warn("\n===== SCHEDULER INTEGRATION TEST! =====\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var worker1 = try worker.Worker.init(alloc);
    defer worker1.deinit();
    var worker2 = try worker.Worker.init(alloc);
    defer worker2.deinit();
    var worker3 = try worker.Worker.init(alloc);
    defer worker3.deinit();

    var workers = [_]*worker.Worker{ &worker1, &worker2, &worker3 };
    var sched = try scheduler.Scheduler.init(alloc, &workers);
    defer sched.deinit();

    std.log.warn("Created persistent workers: {s}, {s}, {s}\n", .{ worker1.id, worker2.id, worker3.id });

    // test 1: First scheduling round
    {
        const selected = try sched.schedule(alloc);
        try std.testing.expectEqual(worker1.id, selected.id);
        std.log.warn("First scheduling selected: {s}\n", .{selected.id});
    }

    // test 2: Second scheduling round with same state
    {
        const selected = try sched.schedule(alloc);
        try std.testing.expectEqual(worker2.id, selected.id);
        std.log.warn("Second scheduling selected: {s}\n", .{selected.id});
    }

    // test 3: Add a task to worker1 and see how it affects scheduling
    {
        const t = try task.Task.init(alloc, "integration-test-task");
        try worker1.enqueueTask(t);
        std.log.warn("Added task to worker1 ({s})\n", .{worker1.id});

        const selected = try sched.schedule(alloc);
        try std.testing.expectEqual(worker3.id, selected.id);
        std.log.warn("Third scheduling selected: {s}\n", .{selected.id});
    }
}

test "launch container" {
    std.log.warn("\n===== TESTING CONTAINER LAUNCH =====\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var w = try worker.Worker.init(alloc);
    defer w.deinit();

    var t = try task.Task.init(alloc, "test-container");
    defer t.deinit();

    // set an simple img then we can change to theia
    try t.setImage("alpine:latest");
    try t.setCommand(&[_][]const u8{ "echo", "Hello from container!" });
    try t.transition(.Scheduled);

    try w.enqueueTask(t);
    try w.startTask(t);

    // check to see if container started
    try std.testing.expect(t.container_id != null);
    std.debug.print("Container ID: {s}\n", .{t.container_id.?});

    // run briefly
    std.time.sleep(1 * std.time.ns_per_s);

    // clean up
    try w.stopTask(t);
}
