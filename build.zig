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

    run_qemu.step.dependOn(b.getInstallStep());

    const test_step = b.step("run", "Run stacktrace example");
    test_step.dependOn(&run_qemu.step);
}
