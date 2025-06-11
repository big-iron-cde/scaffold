const std = @import("std");

// PORT IMPLEMENTATION

pub const Port = struct {
    number: u16,

    pub const Error = error{
        RestrictedPort,
        PortUnavailable,
        NoAvailablePort,
    };

    // list of the RESTRICTED ports
    const restricted_ports = [_]u16{ 22, 80, 443, 2375, 3306, 5432, 6379, 8080, 27017 };

    // min and max port range
    const min_port = 1025;
    const max_port = 65535;

    // initialize with a specific port number
    pub fn init(port_number: u16) Error!Port {
        if (isRestricted(port_number)) {
            return error.RestrictedPort;
        }

        if (!try isAvailable(port_number)) {
            return error.PortUnavailable;
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
            }
        }
        return error.NoAvailablePort;
    }

    // be able to check if the port is in the restricted list
    fn isRestricted(port: u16) bool {
        for (restricted_ports) |restricted| {
            if (port == restricted) return true;
        }
        return false;
    }

    // test if a port is available by trying to bind to it
    fn isAvailable(port: u16) !bool {
        // try to bind to the port to see if it is available
        var server = std.net.StreamServer.init(.{});
        defer server.deinit();

        // going to local but might need to change when developing (?)
        const address = try std.net.Address.parseIp("0.0.0.0", port);

        const listener = server.listen(address) catch |err| {
            if (err == error.AddressInUse) {
                return false;
            }
            return err;
        };
        defer listener.deinit();
        return true;
    }
};

// LISTENER IMPLEMENTATION
