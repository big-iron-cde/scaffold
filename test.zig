const std = @import("std");
const uuid = @import("uuid");
const docker = @import("docker");
const worker = @import("src/worker/worker.zig");
const task = @import("src/task/task.zig");
const scheduler = @import("src/scheduler/scheduler.zig");
const listener = @import("src/listener/listener.zig");

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

    std.log.warn("Task enqueued: ID={s}, State={s}, Worker tasks={d}\n", .{ uuid.urn.serialize(t.ID), @tagName(t.state), w.tasks.count() });
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
    // REMOVE THIS LINE - worker takes ownership
    // defer t.deinit();

    // set an simple img then we can change to theia
    try t.setImage("alpine:latest");
    try t.setCommand(&[_][]const u8{ "echo", "Hello from container!" });
    try t.transition(.Scheduled);

    try w.enqueueTask(t);

    // add error handling for missing image and docker connection
    w.startTask(t) catch |err| switch (err) {
        error.DockerError => {
            std.log.warn("Docker error - you may need to pull the alpine:latest image first", .{});
            // remove task from worker to prevent double-free
            _ = w.tasks.swapRemove(t.ID);
            t.deinit();
            return;
        },
        error.ConnectionRefused => {
            std.log.warn("Docker connection refused - Docker daemon may not be running", .{});
            // remove task from worker to prevent double-free
            _ = w.tasks.swapRemove(t.ID);
            t.deinit();
            return;
        },
        else => return err,
    };

    // check to see if container started
    try std.testing.expect(t.container_id != null);
    std.debug.print("Container ID: {s}\n", .{t.container_id.?});

    // run briefly
    std.time.sleep(1 * std.time.ns_per_s);

    // clean up
    try w.stopTask(t);
}

test "listener basic functionality" {
    std.log.warn("\n===== TESTING LISTENER =====\n", .{});
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // we don't need allocator anymore
    // const alloc = gpa.allocator();

    // initialize the server
    const server = try listener.initZincServer();

    // the port is hardcoded to 2325
    const port: u16 = 2325;
    std.log.warn("Listener initialized on port {d}\n", .{port});

    // start the listener in a separate thread (detached)
    const thread = try std.Thread.spawn(.{}, startListenerThread, .{server});
    thread.detach(); // detach the thread so we don't need to join it

    // give it time to start up
    std.time.sleep(500 * std.time.ns_per_ms);

    // make an HTTP request to the root endpoint
    try testListenerRoot(port);

    // Note: let the server run and don't try to shut it down cleanly
    // so that it will avoid the segmentation fault from improper shutdown
    std.log.warn("Listener test completed successfully\n", .{});
}

// fix the thread function signature
fn startListenerThread(server: anytype) void {
    listener.runServer(server) catch |err| {
        std.log.err("Failed to start listener: {s}", .{@errorName(err)});
    };
}

// update testListenerRoot to use the correct port type
fn testListenerRoot(port: u16) !void {
    // format the URL with the dynamic port
    const url = try std.fmt.allocPrint(std.heap.page_allocator, "http://localhost:{d}/", .{port});
    defer std.heap.page_allocator.free(url);

    // create a client
    var client = std.http.Client{
        .allocator = std.heap.page_allocator,
    };
    defer client.deinit();

    // make the request
    var headers: [4096]u8 = undefined;
    const uri = try std.Uri.parse(url);
    var request = try client.open(.GET, uri, .{ .server_header_buffer = &headers });
    defer request.deinit();

    try request.send();
    try request.finish();
    try request.wait();

    // verify response
    try std.testing.expectEqual(std.http.Status.ok, request.response.status);

    // read the response body
    const body = try request.reader().readAllAlloc(std.heap.page_allocator, 8192);
    defer std.heap.page_allocator.free(body);

    std.log.warn("Response from server: {s}\n", .{body});

    // verify the response contains the expected text
    try std.testing.expect(std.mem.indexOf(u8, body, "Scaffold Listener is running") != null);
}

test "multiple clients see same version" {
    std.log.warn("\n===== TESTING MULTIPLE CLIENTS VERSION ENDPOINT =====\n", .{});
    
    // initialize the server
    const server = try listener.initZincServer();

    // the port is hardcoded to 2325
    const port: u16 = 2325;
    std.log.warn("Version endpoint test initialized on port {d}\n", .{port});

    // start the listener in a separate thread (detached)
    const thread = try std.Thread.spawn(.{}, startListenerThread, .{server});
    thread.detach(); // detach the thread so we don't need to join it

    // give it time to start up
    std.time.sleep(500 * std.time.ns_per_ms);

    // simulate multiple clients accessing the version endpoint
    const num_clients = 3;
    var version_responses: [num_clients][]u8 = undefined;
    
    for (0..num_clients) |i| {
        version_responses[i] = try testVersionEndpoint(port);
        std.log.warn("Client {d} version response: {s}\n", .{ i + 1, version_responses[i] });
        
        // small delay between requests
        std.time.sleep(100 * std.time.ns_per_ms);
    }
    
    // parse JSON responses to verify they contain the same version
    var parsed_responses: [num_clients]std.json.Parsed(std.json.Value) = undefined;
    
    for (0..num_clients) |i| {
        parsed_responses[i] = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, version_responses[i], .{});
    }
    
    // verify all responses have the same version
    const first_version = parsed_responses[0].value.object.get("version").?.string;
    const first_name = parsed_responses[0].value.object.get("name").?.string;
    
    for (1..num_clients) |i| {
        const current_version = parsed_responses[i].value.object.get("version").?.string;
        const current_name = parsed_responses[i].value.object.get("name").?.string;
        
        try std.testing.expectEqualStrings(first_version, current_version);
        try std.testing.expectEqualStrings(first_name, current_name);
        
        std.log.warn("Client {d} confirmed same version: {s}\n", .{ i + 1, current_version });
    }
    
    std.log.warn("All {d} clients see the same version: {s}\n", .{ num_clients, first_version });
    std.log.warn("Version endpoint test completed successfully\n", .{});
}

// helper function to test the version endpoint
fn testVersionEndpoint(port: u16) ![]u8 {
    // format the URL with the dynamic port
    const url = try std.fmt.allocPrint(std.heap.page_allocator, "http://localhost:{d}/version", .{port});
    defer std.heap.page_allocator.free(url);

    // create a client
    var client = std.http.Client{
        .allocator = std.heap.page_allocator,
    };
    defer client.deinit();

    // make the request
    var headers: [4096]u8 = undefined;
    const uri = try std.Uri.parse(url);
    var request = try client.open(.GET, uri, .{ .server_header_buffer = &headers });
    defer request.deinit();

    try request.send();
    try request.finish();
    try request.wait();

    // verify response
    try std.testing.expectEqual(std.http.Status.ok, request.response.status);

    // read the response body
    const body = try request.reader().readAllAlloc(std.heap.page_allocator, 8192);

    return body;
}

test "visitor counter increments for multiple clients" {
    std.log.warn("\n===== TESTING VISITOR COUNTER INCREMENT =====\n", .{});
    
    // initialize the server
    const server = try listener.initZincServer();

    // the port is hardcoded to 2325
    const port: u16 = 2325;
    std.log.warn("Visitor counter test initialized on port {d}\n", .{port});

    // start the listener in a separate thread (detached)
    const thread = try std.Thread.spawn(.{}, startListenerThread, .{server});
    thread.detach(); // detach the thread so we don't need to join it

    // give it time to start up
    std.time.sleep(500 * std.time.ns_per_ms);

    // simulate multiple clients accessing the root endpoint
    const num_visits = 3;
    var visitor_counts: [num_visits]u32 = undefined;
    
    for (0..num_visits) |i| {
        const response = try testRootEndpointForVisitorCount(port);
        defer std.heap.page_allocator.free(response);
        
        // extract visitor count from response
        visitor_counts[i] = try extractVisitorCount(response);
        std.log.warn("Visit {d} - Visitor count: {d}\n", .{ i + 1, visitor_counts[i] });
        
        // small delay between requests
        std.time.sleep(100 * std.time.ns_per_ms);
    }
    
    // verify that visitor counts are incrementing
    for (1..num_visits) |i| {
        try std.testing.expect(visitor_counts[i] > visitor_counts[i-1]);
        std.log.warn("Confirmed visitor count increased from {d} to {d}\n", .{ visitor_counts[i-1], visitor_counts[i] });
    }
    
    std.log.warn("Visitor counter test completed successfully - counts increased from {d} to {d}\n", .{ visitor_counts[0], visitor_counts[num_visits-1] });
}

// helper function to test the root endpoint for visitor count
fn testRootEndpointForVisitorCount(port: u16) ![]u8 {
    // format the URL with the dynamic port
    const url = try std.fmt.allocPrint(std.heap.page_allocator, "http://localhost:{d}/", .{port});
    defer std.heap.page_allocator.free(url);

    // create a client
    var client = std.http.Client{
        .allocator = std.heap.page_allocator,
    };
    defer client.deinit();

    // make the request
    var headers: [4096]u8 = undefined;
    const uri = try std.Uri.parse(url);
    var request = try client.open(.GET, uri, .{ .server_header_buffer = &headers });
    defer request.deinit();

    try request.send();
    try request.finish();
    try request.wait();

    // verify response
    try std.testing.expectEqual(std.http.Status.ok, request.response.status);

    // read the response body
    const body = try request.reader().readAllAlloc(std.heap.page_allocator, 8192);

    return body;
}

// helper function to extract visitor count from response text
fn extractVisitorCount(response: []const u8) !u32 {
    // response format: "Scaffold Listener is running - Visitors: 123"
    const visitors_prefix = "Visitors: ";
    
    if (std.mem.indexOf(u8, response, visitors_prefix)) |start_index| {
        const number_start = start_index + visitors_prefix.len;
        
        // find the end of the number (either end of string or next whitespace)
        var number_end = number_start;
        while (number_end < response.len and std.ascii.isDigit(response[number_end])) {
            number_end += 1;
        }
        
        const number_str = response[number_start..number_end];
        return try std.fmt.parseInt(u32, number_str, 10);
    }
    
    return error.VisitorCountNotFound;
}
