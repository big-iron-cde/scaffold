const std = @import("std");

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


        if (!try isAvailable(port_number)) {

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

    fn isAvailable(port: u16) !bool {
        // try to bind to the port to see if it is available
        var server = std.net.StreamServer.init(.{});
        defer server.deinit();

        // going to local but might need to change when developing (?)
        const address = try std.net.Address.parseIp("0.0.0.0", port);

        const listener = server.listen(address) catch |err| {
            if (err == Error.AddressInUse) {
                return false;
            }
            return err;
        };
        defer listener.deinit();
        return true;
    }
};

// LISTENER IMPLEMENTATION

pub const Listener = struct {
    server: std.net.StreamServer,
    allocator: std.mem.Allocator,
    port: Port,
    is_running: bool,

    // initialize a new listener with an available port
    pub fn init(allocator: std.mem.Allocator) !Listener {
        // find an available port
        const port = try Port.findAvailable();

        return Listener{
            .server = std.net.StremServer.init(.{
                .reuse_address = true,
            }),
            .allocator = allocator,
            .port = port,
            .is_running = false,
        };
    }

    // start the listener and begin acceting connections
    pub fn start(self: *Listener) !void {
        // create the address to listen on
        const address = try std.net.Address.parseIp("0.0.0.0", self.port.number);

        // start listening on the port
        try self.server.listen(address);
        self.is_running = true;

        std.log.info("Listener started on port {d}", .{self.port.number});

        // accept connection until stopped
        while (self.is_running) {
            const connection = self.server.accept() catch |err| {
                std.log.err("Error accepting connection: {s}", .{@errorName(err)});
                continue;
            };

            // handle the connection
            self.handleConnection(connection) catch |err| {
                std.log.err("Error handling connection: {s}", .{@errorName(err)});
            };
        }
    }

    // handle a single connection
    fn handleConnection(self: *Listener, connection: std.net.StreamServer.Connection) !void {
        defer connection.stream.close();

        // read the request
        var buffer: [1024]u8 = undefined;
        const bytes_read = try connection.stream.readAll(&buffer);
        const request = buffer[0..bytes_read];

        // a basic response
        const response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!";

        _ = try connection.stream.writeAll(response);
    }

    // stop the listener
    pub fn stop(self: *Listener) !void {
        if (!self.is_running) return;

        self.is_running = false;
        try self.server.close();
        std.log.info("Listener stopped on port {d}", .{self.port.number});
    }

    // clean up the listener resources
    pub fn deinit(self: *Listener) void {
        if (self.is_running) {
            _ = self.stop();
        }
        self.server.deinit();
    }
};

