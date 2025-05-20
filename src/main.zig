pub fn main() !void {
    // Create a general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Create a HTTP client
    var client = std.http.Client{ .allocator = gpa.allocator() };
    defer client.deinit();

    // Allocate a buffer for server headers
    var headers: [4096]u8 = undefined;

    // Start the HTTP request
    const uri = try std.Uri.parse("http://localhost:2375/images/json");
    var req = try client.open(.GET, uri, .{ .server_header_buffer = &headers });
    defer req.deinit();

    // Send the HTTP request headers
    try req.send();
    // Finish the body of a request
    try req.finish();

    // Waits for a response from the server and parses any headers that are sent
    try req.wait();

    std.debug.print("status={d}\n", .{req.response.status});

    // Create container for body of request
    var body: [65536]u8 = undefined;
    // Read the body of the request into waiting buffer
    _ = try req.readAll(&body);
    // Report the lenght of the body to print appropriate buffer sized chunk
    const length = req.response.content_length orelse return error.NoBodyLength;
    // Print the applicable section of the body
    std.debug.print("{s}", .{body[0..length]});
}

const std = @import("std");
