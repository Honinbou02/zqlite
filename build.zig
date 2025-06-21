//! Use `zig init --strip` next time to generate a project without comments.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the zqlite library
    const lib = b.addStaticLibrary(.{
        .name = "zqlite",
        .root_source_file = b.path("src/zqlite.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Install the library
    b.installArtifact(lib);

    // Create the zqlite executable
    const exe = b.addExecutable(.{
        .name = "zqlite",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link the library to the executable
    exe.root_module.addImport("zqlite", lib.root_module);

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

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.root_module.addImport("zqlite", lib.root_module);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    // Create the PowerDNS example
    const powerdns_example = b.addExecutable(.{
        .name = "powerdns_example",
        .root_source_file = b.path("examples/powerdns_example.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link the library to the example
    powerdns_example.root_module.addImport("zqlite", lib.root_module);

    // Install the example
    b.installArtifact(powerdns_example);

    // Create run step for PowerDNS example
    const run_powerdns_cmd = b.addRunArtifact(powerdns_example);
    run_powerdns_cmd.step.dependOn(b.getInstallStep());

    const run_powerdns_step = b.step("run-powerdns", "Run the PowerDNS example");
    run_powerdns_step.dependOn(&run_powerdns_cmd.step);

    // Create the Cipher DNS example
    const cipher_example = b.addExecutable(.{
        .name = "cipher_dns",
        .root_source_file = b.path("examples/cipher_dns.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link the library to the Cipher example
    cipher_example.root_module.addImport("zqlite", lib.root_module);

    // Install the Cipher example
    b.installArtifact(cipher_example);

    // Create run step for Cipher DNS example
    const run_cipher_cmd = b.addRunArtifact(cipher_example);
    run_cipher_cmd.step.dependOn(b.getInstallStep());

    const run_cipher_step = b.step("run-cipher", "Run the Cipher DNS example");
    run_cipher_step.dependOn(&run_cipher_cmd.step);
}
