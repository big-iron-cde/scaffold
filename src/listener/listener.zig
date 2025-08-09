const std = @import("std");

const NAME = "Scaffold";
const VERSION = "0.1.0";
const TEST_PORT: u16 = 2325;

var VISITOR_COUNT: u32 = 0;

pub const Listener = struct {
    allocator: std.mem.Allocator,
    port: u16,

    pub fn init(allocator: std.mem.Allocator) !Listener {
        return .{
            .allocator = allocator,
            .port = TEST_PORT, // tests assume 2325
        };
    }

    pub fn start(self: *Listener) !void {
        const addr = try std.net.Address.parseIp("0.0.0.0", self.port);
        var tcp = try addr.listen(.{ .reuse_address = true });
        defer tcp.deinit();

        std.log.info("{s} Listener started on port {d}", .{ NAME, self.port });

        while (true) {
            const conn = try tcp.accept();
            self.handleConnection(conn) catch |err| {
                std.log.err("handle error: {s}", .{@errorName(err)});
                conn.stream.close();
            };
        }
    }

    fn handleConnection(_: *Listener, conn_in: std.net.Server.Connection) !void {
        var conn = conn_in; // make mutable so &conn.stream is *Stream
        defer conn.stream.close();

        var buf: [8192]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const A = fba.allocator();

        // ---- Read request line + headers ----
        const header_bytes = try readUntilHeaderEnd(&conn.stream, A);
        if (header_bytes.len == 0) return;

        // Parse the request line
        const first_line_end = std.mem.indexOf(u8, header_bytes, "\r\n") orelse header_bytes.len;
        const request_line = header_bytes[0..first_line_end];
        var it = std.mem.tokenizeAny(u8, request_line, " ");
        const method = it.next() orelse "";
        const target = it.next() orelse "/";
        const path = if (std.mem.indexOfScalar(u8, target, '?')) |q| target[0..q] else target;

        // Body length (if any)
        const content_len = parseContentLength(header_bytes);

        // Read body bytes if present
        var body: []u8 = &[_]u8{};
        if (content_len > 0) {
            body = try A.alloc(u8, content_len);
            var got: usize = 0;
            while (got < content_len) {
                const n = try conn.stream.read(body[got..]);
                if (n == 0) return error.EndOfStream;
                got += n;
            }
        }

        // ---- Routes required by your tests ----
        if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/")) {
            const count = @atomicRmw(u32, &VISITOR_COUNT, .Add, 1, .seq_cst) + 1;
            var msg_buf: [128]u8 = undefined;
            const msg = try std.fmt.bufPrint(&msg_buf, "{s} Listener is running - Visitors: {d}", .{ NAME, count });
            return writeText(&conn.stream, 200, msg);
        }

        if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/version")) {
            var out = std.ArrayList(u8).init(A);
            defer out.deinit();
            try out.writer().print("{{\"name\":\"{s}\",\"version\":\"{s}\"}}", .{ NAME, VERSION });
            return writeJson(&conn.stream, 200, out.items);
        }

        // Fallback
        return writeText(&conn.stream, 404, "not found");
    }
};

// Compatibility functions your tests call
pub fn initZincServer() !Listener {
    return Listener.init(std.heap.page_allocator);
}

pub fn runServer(server_in: Listener) !void {
    var s = server_in;
    try s.start();
}

// -------------------- Helpers --------------------
fn readUntilHeaderEnd(stream: *std.net.Stream, allocator: std.mem.Allocator) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    var tmp: [1024]u8 = undefined;
    while (true) {
        const n = try stream.read(&tmp);
        if (n == 0) break; // EOF
        try list.appendSlice(tmp[0..n]);
        if (std.mem.indexOf(u8, list.items, "\r\n\r\n")) |_| break;
        if (list.items.len > 32 * 1024) break; // cap headers
    }
    const end = std.mem.indexOf(u8, list.items, "\r\n\r\n") orelse list.items.len;
    const extra: usize = if (end + 4 <= list.items.len) @as(usize, 4) else 0;
    const limit = end + extra;

    const owned = try list.toOwnedSlice();
    return owned[0..limit];
}

fn parseContentLength(headers: []const u8) usize {
    var lines = std.mem.tokenizeAny(u8, headers, "\r\n");
    while (lines.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, "Content-Length:")) {
            var it = std.mem.tokenizeAny(u8, line["Content-Length:".len..], " \t");
            if (it.next()) |num| {
                return std.fmt.parseInt(usize, std.mem.trim(u8, num, " \t"), 10) catch 0;
            }
        }
    }
    return 0;
}

fn writeText(stream: *std.net.Stream, status: u16, body: []const u8) !void {
    var w = std.io.bufferedWriter(stream.writer());
    const wr = w.writer();
    try wr.print(
        "HTTP/1.1 {d} OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ status, body.len },
    );
    try wr.writeAll(body);
    try w.flush();
}

fn writeJson(stream: *std.net.Stream, status: u16, body: []const u8) !void {
    var w = std.io.bufferedWriter(stream.writer());
    const wr = w.writer();
    try wr.print(
        "HTTP/1.1 {d} OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ status, body.len },
    );
    try wr.writeAll(body);
    try w.flush();
}
