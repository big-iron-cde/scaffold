// src/store/store.zig
const std = @import("std");
const Task = @import("../task/task.zig").Task;

const c = @cImport({
    @cInclude("hiredis/hiredis.h");
});

pub const Store = struct {
    saveTask: *const fn (self: *anyopaque, t: *const Task) anyerror!void,
    getTask:  *const fn (self: *anyopaque, allocator: std.mem.Allocator, id: []const u8) anyerror!?Task,
    deinit:   *const fn (self: *anyopaque) void,
    ptr: *anyopaque,

    pub fn save(self: *Store, t: *const Task) !void {
        return self.saveTask(self.ptr, t);
    }
    pub fn get(self: *Store, allocator: std.mem.Allocator, id: []const u8) !?Task {
        return self.getTask(self.ptr, allocator, id);
    }
    pub fn deinitStore(self: *Store) void {
        self.deinit(self.ptr);
    }
};

pub const RedisStore = struct {
    ctx: *c.redisContext,

    pub fn init(host: [:0]const u8, port: u16) !RedisStore {
        const raw = c.redisConnect(host, port);
        if (raw == null) return error.RedisConnectionFailed;

        const ctx: *c.redisContext = @ptrCast(raw);
        if (ctx.*.err != 0) {
            c.redisFree(ctx);
            return error.RedisConnectionFailed;
        }
        return .{ .ctx = ctx };
    }

    pub fn deinit(self: *RedisStore) void {
        // ctx is non-null if init succeeded
        c.redisFree(self.ctx);
    }

    // Simple string API (used by your test)
    pub fn set(self: *RedisStore, key: []const u8, value: []const u8) !void {
        return self.setRaw(key, value);
    }
    pub fn get(self: *RedisStore, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        return self.getRaw(allocator, key);
    }

    /// Binary-safe SET using redisCommandArgv (no varargs)
    pub fn setRaw(self: *RedisStore, key: []const u8, value: []const u8) !void {
        // argv: ["SET", key, value]
        const cmd = "SET";
        const argv = [_][*]const u8{ cmd.ptr, key.ptr, value.ptr };
        const lens = [_]usize{ cmd.len, key.len, value.len };

        const raw_reply = c.redisCommandArgv(
            self.ctx,
            @intCast(argv.len),
            // hiredis takes `char **argv` in some headers; drop const on the outer pointer:
            @ptrCast(@constCast(&argv[0])),
            @ptrCast(&lens[0]),
        );

        if (raw_reply == null or self.ctx.*.err != 0) return error.RedisCommandFailed;
        defer c.freeReplyObject(raw_reply);

        const reply: *c.redisReply = @alignCast(@ptrCast(raw_reply));
        if (reply.*.type == c.REDIS_REPLY_ERROR) return error.RedisCommandFailed;
        // OK is fine; nothing else to check
    }

    /// Binary-safe GET using redisCommandArgv (no varargs)
    pub fn getRaw(self: *RedisStore, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        const cmd = "GET";
        const argv = [_][*]const u8{ cmd.ptr, key.ptr };
        const lens = [_]usize{ cmd.len, key.len };

        const raw_reply = c.redisCommandArgv(
            self.ctx,
            @intCast(argv.len),
            @ptrCast(@constCast(&argv[0])),
            @ptrCast(&lens[0]),
        );
        if (raw_reply == null or self.ctx.*.err != 0) return error.RedisCommandFailed;
        defer c.freeReplyObject(raw_reply);

        const reply: *c.redisReply = @alignCast(@ptrCast(raw_reply));

        switch (reply.*.type) {
            c.REDIS_REPLY_NIL => return null,
            c.REDIS_REPLY_STRING => {
                const rlen: usize = @intCast(reply.*.len);
                // hiredis may set str == NULL when len == 0; avoid slicing NULL.
                if (rlen == 0 or reply.*.str == null) {
                    return try allocator.alloc(u8, 0);
                }
                const bytes = reply.*.str[0..rlen];
                return try allocator.dupe(u8, bytes); // dup before free
            },
            else => return error.UnexpectedReplyType,
        }
    }

    // ---- Store adapter for Task (if/when you use it) ----
    pub fn asStore(self: *RedisStore) Store {
        return .{
            .saveTask = saveTaskImpl,
            .getTask  = getTaskImpl,
            .deinit   = deinitImpl,
            .ptr = self,
        };
    }

    fn saveTaskImpl(ctx: *anyopaque, t: *const Task) !void {
        var self: *RedisStore = @ptrCast(@alignCast(ctx));

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const A = gpa.allocator();

        const json = try t.toJson(A);
        defer A.free(json);

        try self.setRaw(t.id[0..], json);
    }

    fn getTaskImpl(ctx: *anyopaque, allocator: std.mem.Allocator, id: []const u8) !?Task {
        var self: *RedisStore = @ptrCast(@alignCast(ctx));
        const maybe = try self.getRaw(allocator, id);
        if (maybe == null) return null;

        const json = maybe.?;
        defer allocator.free(json);

        return try Task.fromJson(allocator, json);
    }

    fn deinitImpl(ctx: *anyopaque) void {
        var self: *RedisStore = @ptrCast(@alignCast(ctx));
        self.deinit();
    }
};
