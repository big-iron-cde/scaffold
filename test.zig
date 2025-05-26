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
    std.log.info("Queue count: {d}", .{w.queue.count()});
}

test "enqueue task" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var w = try worker.Worker.init(alloc);
    defer w.deinit();

    var t = try task.Task.init(alloc, "test-task");
    defer t.deinit();

    try w.enqueueTask(t);

    std.log.info("Task ID: {s}", .{t.ID});
    std.log.info("Task state: {s}", .{@tagName(t.state)});
    std.log.info("Tasks in worker: {d}", .{w.tasks.count()});
}
