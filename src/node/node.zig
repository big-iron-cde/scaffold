const std = @import("std");

pub const Node = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    ip: []const u8,
    memory: u64,
    memory_allocated: u64,
    disk: u64,
    disk_allocated: u64,
    task_count: u32,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, ip: []const u8, memory: u64, disk: u64) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .ip = try allocator.dupe(u8, ip),
            .memory = memory,
            .memory_allocated = 0,
            .disk = disk,
            .disk_allocated = 0,
            .task_count = 0,
        };
        return node;
    }

    pub fn deinit(self: *Node) void {
        self.allocator.free(self.name);
        self.allocator.free(self.ip);
        self.allocator.destroy(self);
    }

    // tracks resource allocation
    pub fn allocateResources(self: *Node, memory: u64, disk: u64) !void {
        if (self.memory_allocated + memory > self.memory) {
            return error.InsufficientMemory;
        }
        if (self.disk_allocated + disk > self.disk) {
            return error.InsufficientDisk;
        }

        self.memory_allocated += memory;
        self.disk_allocated += disk;
        self.task_count += 1;
    }

    // release resources when task completes
    pub fn freeResources(self: *Node, memory: u64, disk: u64) void {
        if (self.memory_allocated >= memory) {
            self.memory_allocated -= memory;
        }
        if (self.disk_allocated >= disk) {
            self.disk_allocated -= disk;
        }
        if (self.task_count > 0) {
            self.task_count -= 1;
        }
    }
};
