const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ---- Executable ----
    const exe = b.addExecutable(.{
        .name = "scaffold",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();                    // NEW
    exe.linkSystemLibrary("hiredis");  // you already had this

    const uuid   = b.dependency("uuid",  .{ .target = target, .optimize = optimize });
    const docker = b.dependency("docker",.{ .target = target, .optimize = optimize });
    const zinc   = b.dependency("zinc",  .{ .target = target, .optimize = optimize });

    exe.root_module.addImport("uuid", uuid.module("uuid"));
    exe.linkLibrary(uuid.artifact("uuid"));

    exe.root_module.addImport("docker", docker.module("docker"));
    exe.linkLibrary(docker.artifact("docker"));

    exe.root_module.addImport("zinc", zinc.module("zinc"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // ---- Unit tests ----
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.linkLibC();                 // NEW
    unit_tests.linkSystemLibrary("hiredis");

    unit_tests.root_module.addImport("uuid",  uuid.module("uuid"));
    unit_tests.root_module.addImport("docker", docker.module("docker"));
    unit_tests.root_module.addImport("zinc",  zinc.module("zinc"));

    b.installArtifact(unit_tests);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
