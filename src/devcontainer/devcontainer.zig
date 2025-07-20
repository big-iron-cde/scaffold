const std = @import("std");
const string = []const u8;

// Implemented from reference located at:
// https://containers.dev/implementors/json_reference/

// The idea here: parse everything into a struct and
// then marshal everything into useful data?

// TODO: Implement the remaining devcontainer spec according
//       to the reference above

pub const DevContainer = struct {
    name: string,
    image: string,
    forwardPorts: [][]const u8
};
