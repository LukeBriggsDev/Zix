const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const kernel = b.addExecutable(.{
        .name = "zix",
        .root_source_file = b.path("src/kernel.zig"),
        .target = target,
        .optimize = .Debug,
        .code_model = .medium,
    });

    b.enable_qemu = true;

    kernel.linker_script = b.path("src/kernel.ld");
    kernel.entry = .{ .symbol_name = "boot" };

    b.installArtifact(kernel);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/kernel.zig"),
        .test_runner = .{
            .path = b.path("src/testing.zig"),
            .mode = .simple,
        },
        .target = target,
    });
    tests.linker_script = b.path("src/kernel.ld");
    tests.entry = .{ .symbol_name = "boot" };
    tests.entry = .disabled;
    tests.root_module.code_model = .medium;

    // run qemu
    const run_qemu = b.addSystemCommand(&[_][]const u8{"qemu-system-riscv64"});
    run_qemu.addArgs(&.{
        "-machine",   "virt",
        "-cpu",       "rv64",
        "-smp",       "1",
        "-m",         "32M",
        "-bios",      "default",
        "-kernel",    b.pathJoin(&.{ b.install_path, "bin", "zix" }),
        "-nographic",
    });

    const run_qemu_test = b.addSystemCommand(&[_][]const u8{"qemu-system-riscv64"});
    run_qemu_test.addArgs(&.{
        "-machine",   "virt",
        "-cpu",       "rv64",
        "-smp",       "1",
        "-m",         "32M",
        "-bios",      "default",
        "-kernel",    b.pathJoin(&.{ b.install_path, "bin", "test" }),
        "-nographic",
    });

    run_qemu.step.dependOn(b.getInstallStep());

    b.installArtifact(tests);

    run_qemu_test.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_qemu_test.step);

    const run_step = b.step("run", "Run stacktrace example");
    run_step.dependOn(&run_qemu.step);
}
