//! Use `zig init --strip` next time to generate a project without comments.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get dependencies
    const zcrypto_dep = b.dependency("zcrypto", .{
        .target = target,
        .optimize = optimize,
    });

    const tokioz_dep = b.dependency("tokioz", .{
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

    // Add dependency modules
    lib.root_module.addImport("zcrypto", zcrypto_dep.module("zcrypto"));
    lib.root_module.addImport("tokioz", tokioz_dep.module("TokioZ"));

    // Install the library
    b.installArtifact(lib);

    // Export the zqlite module for use by other packages
    const zqlite_module = b.addModule("zqlite", .{
        .root_source_file = b.path("src/zqlite.zig"),
        .target = target,
        .optimize = optimize,
    });
    zqlite_module.addImport("zcrypto", zcrypto_dep.module("zcrypto"));
    zqlite_module.addImport("tokioz", tokioz_dep.module("TokioZ"));

    // Create the zqlite executable
    const exe = b.addExecutable(.{
        .name = "zqlite",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link the library to the executable
    exe.root_module.addImport("zqlite", lib.root_module);
    exe.root_module.addImport("zcrypto", zcrypto_dep.module("zcrypto"));
    exe.root_module.addImport("tokioz", tokioz_dep.module("TokioZ"));

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

    // Create the Next-Gen Database example
    const nextgen_example = b.addExecutable(.{
        .name = "nextgen_database",
        .root_source_file = b.path("examples/nextgen_database.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link all modules to the Next-Gen example
    nextgen_example.root_module.addImport("zqlite", lib.root_module);
    nextgen_example.root_module.addImport("zcrypto", zcrypto_dep.module("zcrypto"));
    nextgen_example.root_module.addImport("tokioz", tokioz_dep.module("TokioZ"));

    // Install the Next-Gen example
    b.installArtifact(nextgen_example);

    // Create run step for Next-Gen example
    const run_nextgen_cmd = b.addRunArtifact(nextgen_example);
    run_nextgen_cmd.step.dependOn(b.getInstallStep());

    const run_nextgen_step = b.step("run-nextgen", "Run the Next-Generation Database example");
    run_nextgen_step.dependOn(&run_nextgen_cmd.step);

    // Advanced indexing demo
    const advanced_indexing_demo = b.addExecutable(.{
        .name = "advanced_indexing_demo",
        .root_source_file = b.path("examples/advanced_indexing_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    advanced_indexing_demo.root_module.addImport("zqlite", lib.root_module);
    advanced_indexing_demo.root_module.addImport("zcrypto", zcrypto_dep.module("zcrypto"));
    advanced_indexing_demo.root_module.addImport("tokioz", tokioz_dep.module("TokioZ"));
    b.installArtifact(advanced_indexing_demo);

    // Run step for advanced indexing demo
    const run_advanced_indexing = b.addRunArtifact(advanced_indexing_demo);
    run_advanced_indexing.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_advanced_indexing.addArgs(args);
    }
    const run_advanced_indexing_step = b.step("run-advanced-indexing", "Run the advanced indexing demo");
    run_advanced_indexing_step.dependOn(&run_advanced_indexing.step);

    // Post-Quantum Showcase Example (NEW in v0.5.0)
    const pq_showcase_example = b.addExecutable(.{
        .name = "post_quantum_showcase",
        .root_source_file = b.path("examples/post_quantum_showcase.zig"),
        .target = target,
        .optimize = optimize,
    });
    pq_showcase_example.root_module.addImport("zqlite", lib.root_module);
    pq_showcase_example.root_module.addImport("zcrypto", zcrypto_dep.module("zcrypto"));
    pq_showcase_example.root_module.addImport("tokioz", tokioz_dep.module("TokioZ"));
    b.installArtifact(pq_showcase_example);

    const run_pq_showcase = b.addRunArtifact(pq_showcase_example);
    run_pq_showcase.step.dependOn(b.getInstallStep());
    const run_pq_showcase_step = b.step("run-pq-showcase", "Run the post-quantum showcase demo");
    run_pq_showcase_step.dependOn(&run_pq_showcase.step);

    // Hybrid Crypto Banking Example (NEW in v0.5.0)
    const banking_example = b.addExecutable(.{
        .name = "hybrid_crypto_banking",
        .root_source_file = b.path("examples/hybrid_crypto_banking.zig"),
        .target = target,
        .optimize = optimize,
    });
    banking_example.root_module.addImport("zqlite", lib.root_module);
    banking_example.root_module.addImport("zcrypto", zcrypto_dep.module("zcrypto"));
    banking_example.root_module.addImport("tokioz", tokioz_dep.module("TokioZ"));
    b.installArtifact(banking_example);

    const run_banking = b.addRunArtifact(banking_example);
    run_banking.step.dependOn(b.getInstallStep());
    const run_banking_step = b.step("run-banking", "Run the hybrid crypto banking demo");
    run_banking_step.dependOn(&run_banking.step);
}
