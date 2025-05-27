const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // create the main executable
    const exe = b.addExecutable(.{ .name = "scaffold", .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize });

    const uuid = b.dependency("uuid", .{ .target = target, .optimize = optimize });

    b.installArtifact(exe);

    exe.root_module.addImport("uuid", uuid.module("uuid"));
    exe.linkLibrary(uuid.artifact("uuid"));

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

    unit_tests.root_module.addImport("uuid", uuid.module("uuid"));

    // install and run the tests
    b.installArtifact(unit_tests);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
