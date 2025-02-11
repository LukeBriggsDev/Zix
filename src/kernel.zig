const std = @import("std");
const builtin = @import("builtin");

const sbi = @import("sbi.zig");
const common = @import("common.zig");
const debug = @import("debug.zig");
const testing = @import("testing.zig");

const __bss = @extern([*]u8, .{
    .name = "__bss",
});

const __bss_end = @extern([*]u8, .{
    .name = "__bss_end",
});

const __stack_top = @extern([*]u8, .{
    .name = "__bss_end",
});

var display = common.UARTDisplay{};

var debug_allocator_bytes: [16 * 1024 * 1024]u8 = undefined; // 16 MB

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, ra: ?usize) noreturn {
    _ = stack_trace;
    common.format_print("\n!!!!!!!!!!!!\nKERNEL PANIC\n!!!!!!!!!!!!\n", .{}) catch {};
    common.format_print("panic: {s}\n", .{message}) catch {};

    var debug_allocator = std.heap.FixedBufferAllocator.init(&debug_allocator_bytes);

    var debug_info = debug.DebugInfo.init(debug_allocator.allocator(), .{}) catch |err| {
        common.format_print("panic: debug info err = {}\n", .{err}) catch {};
        hang();
    };

    defer debug_info.deinit();

    debug_info.printStackTrace(display.writer(), ra orelse @returnAddress(), @frameAddress()) catch |err| {
        common.format_print("panic: stacktrace err = {}\n", .{err}) catch {};
    };

    hang();
}

fn hang() noreturn {
    while (true) {}
}

/// Kernel main
export fn kernel_main() noreturn {

    // Zero out bss
    const bss_length: usize = @intFromPtr(__bss_end) - @intFromPtr(__bss);
    var i: usize = 0;
    while (i < bss_length) : (i += 1) __bss[i] = 0;

    if (builtin.is_test) {
        testing.main();
    }

    // Print hello world
    _ = sbi.sbi_putstr("\n\nHello World\n\n");

    hang();
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

const expect = std.testing.expect;
