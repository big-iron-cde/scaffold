const std = @import("std");

// PORT IMPLEMENTATION

pub const Port = struct {
    number: u16,

    // list of the RESTRICTED ports
    const required_ports = [_]u16{ 22, 80, 443, 2375, 3306, 5432, 6379, 8080, 27017 };

    // min and max port range
    const min_port = 1025;
    const max_port = 65535;

    // initialize with a specific port number
    pub fn init(port_number: u16) Port {
        if (isRestricted(port_number)) {
            return error.RestrictedPort;
        }

        if (!try isAvailable(port_number)) {
            return error.PortUnavailable;
        }

        return Port{ .number = port_number };
    }

    // find an available port in the range
    pub fn findAvailable() !Port {
        // initialize a random number generator & seed it
        // with the current time (so it behaves diff every run)
        var prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const random = prng.random();

        // try to find an available port
        var attempts: usize = 0;
        const max_attempts = 1000;

        while (attempts < max_attempts) : {attempts += 1} {
            
        }
    }

    fn isRestricted(port: u16) bool {
        // TODO: be able to check if the port is in the restricted list
    }

    fn isAvailable(port: u16) !bool {
        // test if a port is available by trying to bind to it
    }
};

// LISTENER IMPLEMENTATION
