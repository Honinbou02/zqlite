const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Add Shroud dependency (includes zsync)
    const shroud = b.dependency("shroud", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Create the zqlite library
    const lib = b.addStaticLibrary(.{
        .name = "zqlite",
        .root_source_file = b.path("src/zqlite.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies to library
    lib.root_module.addImport("shroud", shroud.module("shroud"));

    // Install the library
    b.installArtifact(lib);

    // Export the zqlite module for use by other packages
    const zqlite_module = b.addModule("zqlite", .{
        .root_source_file = b.path("src/zqlite.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add dependencies to exported module
    zqlite_module.addImport("shroud", shroud.module("shroud"));

    // Create the zqlite executable
    const exe = b.addExecutable(.{
        .name = "zqlite",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link the library to the executable and add dependencies
    exe.root_module.addImport("zqlite", lib.root_module);
    exe.root_module.addImport("shroud", shroud.module("shroud"));

    // Install the executable
    b.installArtifact(exe);

    // Create run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Create test step
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/zqlite.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add dependencies to tests
    lib_unit_tests.root_module.addImport("shroud", shroud.module("shroud"));

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.root_module.addImport("zqlite", lib.root_module);
    exe_unit_tests.root_module.addImport("shroud", shroud.module("shroud"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    // Basic examples that work without external dependencies
    createBasicExample(b, "powerdns_example", lib, target, optimize, shroud);
    createBasicExample(b, "cipher_dns", lib, target, optimize, shroud);
}

fn createBasicExample(b: *std.Build, name: []const u8, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, shroud: *std.Build.Dependency) void {
    
    const example = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
        .target = target,
        .optimize = optimize,
    });

    example.root_module.addImport("zqlite", lib.root_module);
    example.root_module.addImport("shroud", shroud.module("shroud"));
    b.installArtifact(example);
}