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

    const qemu_args: []const []const u8 = &.{ "qemu-system-riscv64", "-machine", "virt", "-bios", "default", "-nographic", "-serial", "mon:stdio", "--no-reboot", "-kernel", "zig-out/bin/kernel.elf" };

    const qemu_cmd = b.addSystemCommand(qemu_args);

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&qemu_cmd.step);
}
