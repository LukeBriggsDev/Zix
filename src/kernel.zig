const sbi = @import("sbi.zig");
const common = @import("common.zig");

const __stack_top = @extern([*]u8, .{
    .name = "__stack_top",
});

const __bss = @extern([*]u8, .{
    .name = "__bss",
});

const __bss_end = @extern([*]u8, .{
    .name = "__bss_end",
});

/// Kernel main
export fn kernel_main() void {

    // Zero out bss
    const bss_length: usize = @intFromPtr(__bss_end) - @intFromPtr(__bss);
    var i: usize = 0;
    while (i < bss_length) : (i += 1) __bss[i] = 0;

    // Print hello world
    _ = sbi.putstr("\n\nHello World\n\n");
    _ = common.printf("{d} + {d} = {d}", .{ 9, 10, 19 });

    while (true) {}
}

/// Main entry point for the kernel from the SBI
export fn boot() linksection(".text.boot") callconv(.Naked) noreturn {
    asm volatile (
        \\mv sp, %[stack_top] // Set the stack pointer
        \\j kernel_main
        :
        : [stack_top] "r" (__stack_top), // Pass the stack top address as %[stack_top]
    );
}
