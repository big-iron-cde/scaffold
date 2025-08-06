const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "scaffold",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const uuid = b.dependency("uuid", .{ .target = target, .optimize = optimize });
    const docker = b.dependency("docker", .{ .target = target, .optimize = optimize });
    const zinc = b.dependency("zinc", .{ .target = target, .optimize = optimize });

    // Add imports and link dependencies
    exe.root_module.addImport("uuid", uuid.module("uuid"));
    exe.linkLibrary(uuid.artifact("uuid"));

    exe.root_module.addImport("docker", docker.module("docker"));
    exe.linkLibrary(docker.artifact("docker"));

    exe.root_module.addImport("zinc", zinc.module("zinc"));

    // Link hiredis C library
    exe.linkSystemLibrary("hiredis");

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.root_module.addImport("uuid", uuid.module("uuid"));
    unit_tests.root_module.addImport("docker", docker.module("docker"));
    unit_tests.root_module.addImport("zinc", zinc.module("zinc"));
    unit_tests.linkSystemLibrary("hiredis");

    b.installArtifact(unit_tests);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
