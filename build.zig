const std = @import("std");

pub fn build(b: *std.Build) void {
    var DbgAlloc = std.heap.DebugAllocator(.{}){};
    const allocator = DbgAlloc.allocator();
    b.enable_qemu = true;

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    // Modules
    const module_arch = b.addModule("arch", .{
        .root_source_file = b.path("src/arch/arch.zig"),
        .target = target,
    });

    const module_io = b.addModule("io", .{
        .root_source_file = b.path("src/io/io.zig"),
        .target = target,
    });
    module_io.addImport("arch", module_arch);

    const module_mem = b.addModule("mem", .{
        .root_source_file = b.path("src/mem/mem.zig"),
        .target = target,
    });

    const module_proc = b.addModule("proc", .{
        .root_source_file = b.path("src/proc/process.zig"),
        .target = target,
        .optimize = .Debug,
    });
    module_proc.addImport("arch", module_arch);
    module_proc.addImport("mem", module_mem);

    // Kernel
    const kernel = b.addExecutable(.{
        .name = "zix",
        .root_source_file = b.path("src/kernel.zig"),
        .target = target,
        .optimize = .Debug,
        .code_model = .medium,
    });
    kernel.linker_script = b.path("src/kernel.ld");
    kernel.entry = .{ .symbol_name = "boot" };

    // Add kernel imports
    var mod_iter = b.modules.iterator();
    while (mod_iter.next()) |module| {
        kernel.root_module.addImport(module.key_ptr.*, module.value_ptr.*);
    }

    // Install kernel
    const kernel_install_step = b.addInstallArtifact(kernel, .{});

    // Kernel run step
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
    run_qemu.step.dependOn(&kernel_install_step.step);

    const run_step = b.step("run", "Run stacktrace example");
    run_step.dependOn(&run_qemu.step);

    // Tests
    const test_step = b.step("test", "Run tests");
    mod_iter.reset();
    while (mod_iter.next()) |module| {
        const test_mod = b.addTest(.{
            .name = module.key_ptr.*,
            .root_module = module.value_ptr.*,
            .test_runner = .{
                .path = b.path("src/testing.zig"),
                .mode = .simple,
            },
            .target = target,
        });
        const options = b.addOptions();
        options.addOption([]const u8, "module_name", module.key_ptr.*);
        test_mod.linker_script = b.path("src/kernel.ld");
        test_mod.entry = .{ .symbol_name = "boot" };
        test_mod.entry = .disabled;
        test_mod.root_module.code_model = .medium;
        test_mod.root_module.addOptions("config", options);

        // Arch module is a requirement for testing
        test_mod.root_module.addImport("arch", module_arch);

        // Io module is a requirement for testing
        test_mod.root_module.addImport("io", module_io);

        // Add install step
        const run_qemu_test = b.addSystemCommand(&[_][]const u8{"qemu-system-riscv64"});
        run_qemu_test.addArgs(&.{
            "-machine",   "virt",
            "-cpu",       "rv64",
            "-smp",       "1",
            "-m",         "128M",
            "-bios",      "default",
            "-kernel",    b.pathJoin(&.{ b.install_path, "test", "bin", module.key_ptr.* }),
            "-nographic",
        });

        const test_log = std.fmt.allocPrint(
            allocator,
            "test/output/test-{s}.log",
            .{module.key_ptr.*},
        ) catch {
            unreachable;
        };
        defer allocator.free(test_log);
        const write_stdout_step = b.addInstallFile(
            run_qemu_test.captureStdOut(),
            test_log,
        );

        const install_test = b.addInstallArtifact(
            test_mod,
            .{ .dest_dir = .{
                .override = .{ .custom = "test/bin" },
            } },
        );

        test_step.dependOn(&write_stdout_step.step);
        write_stdout_step.step.dependOn(&run_qemu_test.step);
        run_qemu_test.step.dependOn(&install_test.step);
    }
}
