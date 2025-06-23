const std = @import("std");
const zinc = @import("zinc");

// global visitor counter
var visitor_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

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
        var prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const random = prng.random();
        // try to find an available port
        var attempts: usize = 0;
        const max_attempts = 1000;

        while (attempts < max_attempts) : (attempts += 1) {
            // generate a random port number in our range
            const port_number = random.intRangeAtMost(u16, min_port, max_port);

            // check if the port is restricted
            if (isRestricted(port_number)) {
                continue; // skip restricted ports
            }

            // check if the port is available
            if (try isAvailable(port_number)) {
                return Port{ .number = port_number };
            } else {
                std.log.err("Port {d} is unavailable, trying another...", .{port_number});
            }
        }
        return Error.NoAvailablePort;
    }

    // be able to check if the port is in the restricted list
    fn isRestricted(port: u16) bool {
        for (restricted_ports) |restricted| {
            if (port == restricted) return true;
        }
        return false;
    }

    // test if a port is available by trying to bind to it
    fn isAvailable(port: u16) bool {

        // going to local but might need to change when developing (?)
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
/// Initialize and set up a zinc server on port 2325
pub fn initZincServer() !*zinc.Engine {
    // Use constant port 2325
    const port = try Port.init(2325);

    // Initialize zinc with our port
    var server = try zinc.init(.{ .port = port.number });

    // Set up routes
    var router = server.getRouter();
    try router.get("/", rootHandler);
    try router.get("/version", versionHandler);

    // Print the router configuration
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
