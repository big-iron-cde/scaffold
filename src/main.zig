const std = @import("std");
const listener = @import("listener/listener.zig");
const task = @import("task/task.zig");
const worker = @import("worker/worker.zig");
const zinc = @import("zinc");

// simple session storage
var session_map: std.StringHashMap(u16) = undefined;
var worker_instance: ?*worker.Worker = null;
var allocator: std.mem.Allocator = undefined;
var next_port: u16 = 3001;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    // initialize session storage
    session_map = std.StringHashMap(u16).init(allocator);
    defer session_map.deinit();

    // initialize worker
    const worker_ptr = try allocator.create(worker.Worker);
    worker_ptr.* = try worker.Worker.init(allocator);
    worker_instance = worker_ptr;
    defer {
        if (worker_instance) |w| {
            w.deinit();
            allocator.destroy(w);
        }
    }

    // initialize server with additional routes
    const port = try listener.Port.init(2325);
    var server = try zinc.init(.{ .port = port.number });
    defer server.deinit();

    var router = server.getRouter();
    try router.get("/", rootHandler);
    try router.get("/version", versionHandler);
    try router.get("/request-container", requestContainerHandler);

    router.printRouter();
    std.log.info("Scaffold server with container driver running on port {d}", .{port.number});

    try server.run();
}

fn rootHandler(ctx: *zinc.Context) !void {
    try ctx.text("Scaffold Container Driver - Visit /request-container to get a container", .{});
}

fn versionHandler(ctx: *zinc.Context) !void {
    try ctx.json(.{
        .version = "0.1.0",
        .name = "Scaffold Container Driver",
        .timestamp = std.time.timestamp(),
    }, .{});
}

// new container request handler
fn requestContainerHandler(ctx: *zinc.Context) !void {
    // generate simple user ID
    const timestamp = std.time.timestamp();
    const user_id = try std.fmt.allocPrint(ctx.allocator, "user-{d}", .{timestamp});
    defer ctx.allocator.free(user_id);

    // check if user already has a container
    if (session_map.get(user_id)) |existing_port| {
        const redirect_url = try std.fmt.allocPrint(ctx.allocator, "http://localhost:{d}", .{existing_port});
        defer ctx.allocator.free(redirect_url);

        try ctx.json(.{
            .status = "existing",
            .user_id = user_id,
            .container_port = existing_port,
            .redirect_url = redirect_url,
        }, .{});
        return;
    }

    // get next available port
    const container_port = getNextPort() catch {
        try ctx.json(.{
            .@"error" = "No ports available",
            .message = "All container ports are in use",
        }, .{});
        return;
    };

    // create and start container
    createUserContainer(user_id, container_port) catch {
        std.log.err("Failed to create container", .{});
        try ctx.json(.{
            .@"error" = "Container creation failed",
            .message = "Could not start container",
        }, .{});
        return;
    };

    // store session
    try session_map.put(try allocator.dupe(u8, user_id), container_port);

    const redirect_url = try std.fmt.allocPrint(ctx.allocator, "http://localhost:{d}", .{container_port});
    defer ctx.allocator.free(redirect_url);

    try ctx.json(.{
        .status = "created",
        .user_id = user_id,
        .container_port = container_port,
        .redirect_url = redirect_url,
        .message = "Container created! Access it at the redirect_url",
    }, .{});
}

fn getNextPort() !u16 {
    while (next_port < 4000) : (next_port += 1) {
        const port = listener.Port.init(next_port) catch {
            continue; // port not available, try next
        };
        next_port += 1;
        return port.number;
    }
    return error.NoAvailablePort;
}

fn createUserContainer(user_id: []const u8, port: u16) !void {
    const w = worker_instance orelse return error.WorkerNotInitialized;

    // create task for container - use a simple image that will run
    const container_task = try task.Task.init(allocator, "user-container");
    try container_task.setImage("hello-world");

    // set port environment variable (though hello-world won't use it)
    const port_env = try std.fmt.allocPrint(allocator, "PORT={d}", .{port});
    defer allocator.free(port_env);
    try container_task.addEnv(port_env);

    // start the container
    try w.startTask(container_task);

    std.log.info("Created container for user {s} on port {d}", .{ user_id, port });
}
