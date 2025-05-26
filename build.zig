const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // create module for the main application
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // export the worker module so it can be imported in test.zig
    _ = b.createModule(.{
        .name = "worker",
        .root_source_file = b.path("src/worker/worker.zig"),
        .target = target,
        .optimize = optimize,
    });

    // export the task module so it can be imported in test.zig
    _ = b.createModule(.{
        .name = "task",
        .root_source_file = b.path("src/task/task.zig"),
        .target = target,
        .optimize = optimize,
    });

    // create the main executable
    const exe = b.addExecutable(.{
        .name = "scaffold",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    // setup run command
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // THIS IS THE KEY PART - create a separate test that uses test.zig directly
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // install and run the tests
    b.installArtifact(unit_tests);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
