const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const elf = b.addExecutable(.{
        .name = "kernel.elf",
        .root_source_file = b.path("src/kernel.zig"),
        .target = target,
        .optimize = .Debug,
        .code_model = .medium,
    });

    elf.linker_script = b.path("src/kernel.ld");
    elf.entry = .{ .symbol_name = "boot" };

    b.installArtifact(elf);
}
