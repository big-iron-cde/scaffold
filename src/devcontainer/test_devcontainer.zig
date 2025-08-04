const std = @import("std");
const devcontainer = @import("../devcontainer/devcontainer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse your devcontainer.json
    const container = try devcontainer.parseFromFile(allocator, ".devcontainer/devcontainer.json");

    // Print the parsed values
    if (container.name) |name_val| {
        std.debug.print("Container name: {s}\n", .{name_val.string});
    } else {
        std.debug.print("Container name: (none)\n", .{});
    }
    if (container.image) |image_val| {
        std.debug.print("Container image: {s}\n", .{image_val.string});
    } else {
        std.debug.print("Container image: (none)\n", .{});
    }

    if (container.forwardPorts) |ports| {
        std.debug.print("Forward ports: ", .{});
        for (ports) |port| {
            std.debug.print("{s} ", .{port});
        }
        std.debug.print("\n", .{});
    }
}
