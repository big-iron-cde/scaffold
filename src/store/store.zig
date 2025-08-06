// store.zig
// RedisStore uses hiredis C library to store and retrieve task data from Redis

const std = @import("std");
const Task = @import("../task/task.zig").Task;

const c = @cImport({
    @cInclude("hiredis/hiredis.h");
});

pub const RedisStore = struct {
    context: *c.redisContext,

    pub fn init() !RedisStore {
        const raw_ctx = c.redisConnect("127.0.0.1", 6379);
        if (raw_ctx == null) return error.RedisConnectionFailed;

        const ctx: *c.redisContext = @ptrCast(raw_ctx);
        if (ctx.*.err != 0) return error.RedisConnectionFailed;

        return RedisStore{ .context = ctx };
    }

    pub fn deinit(self: *RedisStore) void {
        c.redisFree(self.context);
    }

    pub fn saveTask(self: *RedisStore, key: []const u8, task_data: []const u8) !void {
        const cmd = try std.fmt.allocPrint(std.heap.page_allocator, "SET {s} {s}", .{ key, task_data });
        defer std.heap.page_allocator.free(cmd);

        const reply = c.redisCommand(self.context, "%s", cmd.ptr);
        if (reply == null) return error.RedisCommandFailed;
        defer c.freeReplyObject(reply);
    }

    pub fn getTask(self: *RedisStore, key: []const u8, allocator: std.mem.Allocator) !?[]u8 {
        const cmd = try std.fmt.allocPrint(allocator, "GET {s}", .{ key });
        defer allocator.free(cmd);

        const raw = c.redisCommand(self.context, "%s", cmd.ptr);
        if (raw == null) return error.RedisCommandFailed;
        defer c.freeReplyObject(raw);

        const reply: *c.redisReply = @alignCast(@ptrCast(raw));
        if (reply.*.type != c.REDIS_REPLY_STRING) return null;

        const str = reply.*.str[0..reply.*.len];
        return try allocator.dupe(u8, str); // ← FIXED HERE
    }
};
