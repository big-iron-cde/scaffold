const std = @import("std");
const worker = @import("src/worker/worker.zig");
const task = @import("src/task/task.zig");

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
