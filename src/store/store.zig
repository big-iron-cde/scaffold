const std = @import("std");
const okredis = @import("redis");
const Task = @import("task").Task;

// RedisStore wraps a Redis client for saving and retrieving tasks
pub const RedisStore = struct {
    client: okredis.Client,

    // initialize a RedisStore by connecting to Redis on localhost:6379
    pub fn init() !RedisStore {
        // parse the Redis server address
        const address = try std.net.Address.parseIp("127.0.0.1", 6379);

        // connect to the Redis server
        const conn = try std.net.tcpConnectToAddress(address);

        // allocate read and write buffers for Redis client
        const allocator = std.heap.page_allocator;

        // create the Redis client with buffers
        const client = try okredis.Client.init(conn, .{
            .reader_buffer = try allocator.alloc(u8, 4096),
            .writer_buffer = try allocator.alloc(u8, 4096),
        });

        return RedisStore{ .client = client };
    }

    // free resources used by the Redis client
    pub fn deinit(self: *RedisStore) void {
        self.client.deinit();
    }

    // save a task to Redis using the given key
    pub fn saveTask(self: *RedisStore, key: []const u8, task_data: []const u8) !void {
        try self.client.set(key, task_data);
    }

    // retrieve a task from Redis using the given key
    pub fn getTask(self: *RedisStore, key: []const u8, allocator: std.mem.Allocator) !?[]u8 {
        return try self.client.getAlloc(allocator, key);
    }
};
