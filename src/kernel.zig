const sbi = @import("sbi.zig");
const common = @import("common.zig");
const std = @import("std");

const __stack_top = @extern([*]u8, .{
    .name = "__stack_top",
});

const __bss = @extern([*]u8, .{
    .name = "__bss",
});

const __bss_end = @extern([*]u8, .{
    .name = "__bss_end",
});

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, ra: ?usize) noreturn {
    _ = stack_trace;
    _ = ra;
    _ = common.format_print("\n!!!!!!!!!!!!\nKERNEL PANIC\n!!!!!!!!!!!!\n", .{}) catch {};
    _ = common.format_print("{s}\n", .{message}) catch {};
    while (true) {}
}

/// Kernel main
export fn kernel_main() void {

    // Zero out bss
    const bss_length: usize = @intFromPtr(__bss_end) - @intFromPtr(__bss);
    var i: usize = 0;
    while (i < bss_length) : (i += 1) __bss[i] = 0;

    // Print hello world
    _ = sbi.sbi_putstr("\n\nHello World\n\n");
    _ = common.format_print("{d} + {d} = {d}", .{ 9, 10, 19 }) catch {
        _ = sbi.sbi_putstr("printf err");
    };

    var x: u8 = 255;
    x = x + 1;

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
