const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Add zsync dependency for async operations
    const zsync = b.dependency("zsync", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Create the zqlite library - now with only zsync dependency!
    const lib = b.addLibrary(.{
        .name = "zqlite",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zqlite.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add zsync dependency to library
    lib.root_module.addImport("zsync", zsync.module("zsync"));

    // Install the library
    b.installArtifact(lib);

    // Create C library for FFI
    const c_lib = b.addLibrary(.{
        .name = "zqlite_c",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ffi/c_api.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link the main library to the C FFI
    c_lib.root_module.addImport("zqlite", lib.root_module);
    c_lib.root_module.addImport("zsync", zsync.module("zsync"));

    // Install the C library
    b.installArtifact(c_lib);

    // Export the zqlite module for use by other packages
    const zqlite_module = b.addModule("zqlite", .{
        .root_source_file = b.path("src/zqlite.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add zsync dependency to exported module
    zqlite_module.addImport("zsync", zsync.module("zsync"));

    // Create the zqlite executable
    const exe = b.addExecutable(.{
        .name = "zqlite",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link the library to the executable
    exe.root_module.addImport("zqlite", lib.root_module);
    exe.root_module.addImport("zsync", zsync.module("zsync"));

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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zqlite.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    // Add zsync dependency to tests
    lib_unit_tests.root_module.addImport("zsync", zsync.module("zsync"));

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe_unit_tests.root_module.addImport("zqlite", lib.root_module);
    exe_unit_tests.root_module.addImport("zsync", zsync.module("zsync"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    // Basic examples that work without external dependencies
    createBasicExample(b, "powerdns_example", lib, target, optimize, zsync);
    createBasicExample(b, "cipher_dns", lib, target, optimize, zsync);
    
    // v1.2.2 Universal API examples
    createBasicExample(b, "universal_api_demo", lib, target, optimize, zsync);
    createBasicExample(b, "web_backend_demo", lib, target, optimize, zsync);
    
    // v1.3.0 PostgreSQL compatibility demos
    createDemo(b, "uuid_demo", lib, target, optimize, zsync);
    createDemo(b, "json_demo", lib, target, optimize, zsync);
    createDemo(b, "connection_pool_demo", lib, target, optimize, zsync);
    createDemo(b, "window_functions_demo", lib, target, optimize, zsync);
    // createDemo(b, "query_cache_demo", lib, target, optimize, zsync); // TODO: Fix DoublyLinkedList API for Zig 0.16
    createDemo(b, "array_operations_demo", lib, target, optimize, zsync);

    // Ghostwire integration demo
    createBasicExample(b, "ghostwire_integration_demo", lib, target, optimize, zsync);
}

fn createBasicExample(b: *std.Build, name: []const u8, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, zsync: *std.Build.Dependency) void {
    
    const example = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
        }),
    });

    example.root_module.addImport("zqlite", lib.root_module);
    example.root_module.addImport("zsync", zsync.module("zsync"));
    b.installArtifact(example);
}

fn createDemo(b: *std.Build, name: []const u8, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, zsync: *std.Build.Dependency) void {
    
    const demo = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("src/examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
        }),
    });

    demo.root_module.addImport("zqlite", lib.root_module);
    demo.root_module.addImport("zsync", zsync.module("zsync"));
    b.installArtifact(demo);
}