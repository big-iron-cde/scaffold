const std = @import("std");
const string = []const u8;

// Implemented from reference located at:
// https://containers.dev/implementors/json_reference/

// The idea here: parse everything into a struct and
// then marshal everything into useful data?

// TODO: Implement the remaining devcontainer spec according
//       to the reference above

// port attributes for portsAttributes and otherPortsAttributes
pub const PortAttributes = struct {
    label: ?string = null,
    protocol: ?enum { http, https } = null,
    onAutoForward: ?enum { notify, openBrowser, openBrowserOnce, openPreview, silent, ignore } = null,
    requireLocalPort: ?bool = null,
    elevateIfNeeded: ?bool = null,
};

// build configuration for Docker images
pub const BuildConfig = struct {
    dockerfile: ?string = null,
    context: ?string = null,
    args: ?std.json.Value = null,
    options: ?[]string = null,
    target: ?string = null,
    cacheFrom: ?[]string = null,
};

// host requirements specification
pub const HostRequirements = struct {
    cpus: ?i32 = null,
    memory: ?string = null,
    storage: ?string = null,
    gpu: ?union(enum) {
        boolean: bool,
        optional: void,
        object: struct {
            cores: ?i32 = null,
            memory: ?string = null,
        },
    } = null,
};

containerEnv: ?std.json.Value = null,
pub const Mount = struct {
    source: string,
    target: string,
    type: enum { bind, volume, tmpfs },
    consistency: ?enum { cached, delegated, consistent } = null,
};

// lifecycle command
pub const LifecycleCommand = union(enum) {
    string: string,
    array: []string,
    object: std.json.Value,
};

pub const DevContainer = struct {
    name: ?std.json.Value = null,
    image: ?std.json.Value = null,
    build: ?BuildConfig = null,
    forwardPorts: ?[]string = null,
    portsAttributes: ?std.json.Value = null,
    otherPortsAttributes: ?std.json.Value = null,
    appPort: ?union(enum) {
        single: i32,
        multiple: []i32,
        string: string,
    } = null,

    // env variables
    containerEnv: ?std.json.Value = null,
    remoteEnv: ?std.json.Value = null,

    // user configuration
    remoteUser: ?string = null,
    containerUser: ?string = null,
    updateRemoteUserUID: ?bool = null,
    userEnvProbe: ?enum { none, interactiveShell, loginShell, loginInteractiveShell } = null,

    // container behavior
    overrideCommand: ?bool = null,
    shutdownAction: ?enum { none, stopContainer, stopCompose } = null,
    init: ?bool = null,
    privileged: ?bool = null,
    capAdd: ?[]string = null,
    securityOpt: ?[]string = null,
    runArgs: ?[]string = null,

    // mounts and workspace
    mounts: ?[]Mount = null,
    workspaceMount: ?string = null,
    workspaceFolder: ?string = null,

    // Docker Compose specific
    dockerComposeFile: ?union(enum) {
        single: string,
        multiple: []string,
    } = null,
    service: ?string = null,
    runServices: ?[]string = null,

    // features and customizations
    features: ?std.json.Value = null,
    overrideFeatureInstallOrder: ?[]string = null,
    customizations: ?std.json.Value = null,

    // lifecycle scripts
    initializeCommand: ?LifecycleCommand = null,
    onCreateCommand: ?LifecycleCommand = null,
    updateContentCommand: ?LifecycleCommand = null,
    postCreateCommand: ?LifecycleCommand = null,
    postStartCommand: ?LifecycleCommand = null,
    postAttachCommand: ?LifecycleCommand = null,
    waitFor: ?enum { initializeCommand, onCreateCommand, updateContentCommand } = null,

    // host requirements
    hostRequirements: ?HostRequirements = null,
};

// parse a devcontainer.json file
pub fn parseFromFile(allocator: std.mem.Allocator, file_path: []const u8) !DevContainer {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    defer allocator.free(content);

    _ = try file.readAll(content);

    return parseFromJson(allocator, content);
}

// parse JSON content into DevContainer struct
pub fn parseFromJson(allocator: std.mem.Allocator, json_content: []const u8) !DevContainer {
    const parsed = try std.json.parseFromSlice(DevContainer, allocator, json_content, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return parsed.value;
}
