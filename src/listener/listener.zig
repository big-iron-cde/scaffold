const std = @import("std");
const zinc = @import("zinc");

// global visitor counter
var visitor_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

// simple user port tracking
var user_ports: std.StringHashMap(u16) = undefined;
var allocated_ports: std.ArrayList(u16) = undefined;
var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

pub fn initPortTracking() void {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    user_ports = std.StringHashMap(u16).init(allocator);
    allocated_ports = std.ArrayList(u16).init(allocator);
}

// PORT IMPLEMENTATION

pub const Port = struct {
    number: u16,

    pub const Error = error{
        RestrictedPort,
        PortUnavailable,
        NoAvailablePort,
        AddressInUse,
    };

    // list of the RESTRICTED ports
    const restricted_ports = [_]u16{ 22, 80, 443, 2375, 3306, 5432, 6379, 8080, 27017 };

    // min and max port range
    const min_port = 1025;
    const max_port = 65535;

    // initialize with a specific port number
    pub fn init(port_number: u16) Error!Port {
        if (isRestricted(port_number)) {
            return Error.RestrictedPort;
        }

        if (!isAvailable(port_number)) {
            return Error.PortUnavailable;
        }

        return Port{ .number = port_number };
    }

    // find an available port in the range
    pub fn findAvailable() Error!Port {
        // initialize a random number generator & seed it
        // with the current time (so it behaves diff every run)
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const random = prng.random();
        // try to find an available port
        var attempts: usize = 0;
        const max_attempts = 1000;

        while (attempts < max_attempts) : (attempts += 1) {
            // generate a random port number in our range
            const port_number = random.intRangeAtMost(u16, min_port, max_port);

            // check if the port is restricted
            if (isRestricted(port_number) or isAllocated(port_number)) {
                continue; // skip restricted ports
            }

            // check if the port is available
            if (isAvailable(port_number)) {
                allocated_ports.append(port_number) catch {};
                return Port{ .number = port_number };
            }
        }
        return Error.NoAvailablePort;
    }

    // get or assign port for user
    pub fn forUser(user_id: []const u8) Error!Port {
        // check if user already has a port
        if (user_ports.get(user_id)) |existing_port| {
            return Port{ .number = existing_port };
        }

        // get new port and assign to user
        const port = try findAvailable();
        user_ports.put(user_id, port.number) catch {};

        std.log.info("Assigned port {d} to user: {s}", .{ port.number, user_id });
        return port;
    }

    // release user's port
    pub fn releaseUser(user_id: []const u8) void {
        if (user_ports.get(user_id)) |port_num| {
            _ = user_ports.remove(user_id);
            // remove from allocated list
            for (allocated_ports.items, 0..) |port, i| {
                if (port == port_num) {
                    _ = allocated_ports.swapRemove(i);
                    break;
                }
            }
            std.log.info("Released port {d} for user: {s}", .{ port_num, user_id });
        }
    }

    fn isRestricted(port: u16) bool {
        for (restricted_ports) |restricted| {
            if (port == restricted) return true;
        }
        return false;
    }

    // check if port is already allocated to someone
    fn isAllocated(port: u16) bool {
        for (allocated_ports.items) |allocated| {
            if (port == allocated) return true;
        }
        return false;
    }

    fn isAvailable(port: u16) bool {
        const address = std.net.Address.resolveIp("0.0.0.0", port) catch |err| {
            std.log.err("{any}", .{err});
            return false;
        };

        var listener = address.listen(.{ .reuse_address = true }) catch |err| {
            if (err == Error.AddressInUse) {
                std.log.err("{any}", .{err});
            }
            return false;
        };
        defer listener.deinit();
        return true;
    }
};

// LISTENER FUNCTIONS
pub fn initZincServer() !*zinc.Engine {
    // initialize port tracking
    initPortTracking();

    // Use constant port 2325
    const port = try Port.init(2325);

    var server = try zinc.init(.{ .port = port.number });

    var router = server.getRouter();
    try router.get("/", rootHandler);
    try router.get("/version", versionHandler);
    // endpoints for container port management
    try router.get("/port/:user_id", getUserPortHandler);
    try router.post("/assign/:user_id", assignPortHandler);

    router.printRouter();
    std.log.info("Zinc server initialized on port {d}", .{port.number});

    return server;
}

/// run the server (this will block until shutdown)
pub fn runServer(server: *zinc.Engine) !void {
    try server.run();
}

pub fn shutdownServer(server: *zinc.Engine) !void {
    server.deinit();
    std.log.info("Zinc server has been shut down", .{});
}

// handler functions
fn rootHandler(ctx: *zinc.Context) !void {
    // increment visitor count to test
    const current_visitors = visitor_count.fetchAdd(1, .monotonic) + 1;

    const message = try std.fmt.allocPrint(ctx.allocator, "Scaffold Listener is running - Visitors: {d}", .{current_visitors});
    defer ctx.allocator.free(message);

    try ctx.text(message, .{});
}

fn versionHandler(ctx: *zinc.Context) !void {
    const current_visitors = visitor_count.load(.monotonic);

    try ctx.json(.{
        .version = "0.1.0",
        .name = "Scaffold Listener",
        .timestamp = std.time.timestamp(),
        .current_visitors = current_visitors,
    }, .{});
}

// simple handlers for port management
fn getUserPortHandler(ctx: *zinc.Context) !void {
    // get user_id from URL path parameter using Zinc's correct API
    const user_param = ctx.getParam("user_id") orelse {
        try ctx.json(.{ .@"error" = "Missing user_id parameter" }, .{ .status = .bad_request });
        return;
    };
    const user_id = user_param.value;

    if (user_ports.get(user_id)) |port| {
        try ctx.json(.{ .user_id = user_id, .port = port }, .{});
    } else {
        try ctx.json(.{ .@"error" = "No port assigned" }, .{ .status = .not_found });
    }
}

fn assignPortHandler(ctx: *zinc.Context) !void {
    // get user_id from URL path parameter
    const user_param = ctx.getParam("user_id") orelse {
        try ctx.json(.{ .@"error" = "Missing user_id parameter" }, .{ .status = .bad_request });
        return;
    };
    const user_id = user_param.value;

    const port = Port.forUser(user_id) catch |err| {
        try ctx.json(.{ .@"error" = @errorName(err) }, .{ .status = .internal_server_error });
        return;
    };

    try ctx.json(.{ .user_id = user_id, .assigned_port = port.number }, .{});
}
