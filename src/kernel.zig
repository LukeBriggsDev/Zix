const sbi = @import("sbi.zig");

const __stack_top = @extern([*]u8, .{
    .name = "__stack_top",
});

const __bss = @extern([*]u8, .{
    .name = "__bss",
});

const __bss_end = @extern([*]u8, .{
    .name = "__bss_end",
});

export fn kernel_main() void {
    const bss_length: usize = @intFromPtr(__bss_end) - @intFromPtr(__bss);
    var i: usize = 0;
    while (i < bss_length) : (i += 1) __bss[i] = 0;

    _ = sbi.put_str("\n\nHello World\n\n");

    while (true) {}
}

export fn boot() linksection(".text.boot") callconv(.Naked) noreturn {
    asm volatile (
        \\mv sp, %[stack_top] // Set the stack pointer
        \\j kernel_main
        :
        : [stack_top] "r" (__stack_top), // Pass the stack top address as %[stack_top]
    );
}
