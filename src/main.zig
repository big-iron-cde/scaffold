const std = @import("std");
const listener = @import("listener/listener.zig");
const store_mod = @import("store.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var redis_impl = try store_mod.RedisStore.init("127.0.0.1", 6379);
    var store = redis_impl.asStore();
    defer store.deinitStore();

    var srv = try listener.Listener.init(A, &store);
    defer srv.deinit();

    try srv.start();
}
