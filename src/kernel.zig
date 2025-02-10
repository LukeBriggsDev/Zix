const std = @import("std");
const builtin = @import("builtin");

const sbi = @import("sbi.zig");
const common = @import("common.zig");
const debug = @import("debug.zig");

const __bss = @extern([*]u8, .{
    .name = "__bss",
});

const __bss_end = @extern([*]u8, .{
    .name = "__bss_end",
});

const __stack_top = @extern([*]u8, .{
    .name = "__bss_end",
});

/// Standard Library Options
pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = logFn,
};

var display = common.UARTDisplay{};

/// Logging function
pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const color = comptime switch (level) {
        .debug => "\x1b[32m",
        .info => "\x1b[36m",
        .warn => "\x1b[33m",
        .err => "\x1b[31m",
    };
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ color ++ comptime level.asText() ++ "\x1b[0m] " ++ scope_prefix;
    common.format_print(prefix ++ format ++ "\n", args);
}

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

pub fn test_main() noreturn {
    for (builtin.test_functions) |t| {
        t.func() catch |err| {
            std.fmt.format(display.writer(), "{s} fail: {}\n", .{ t.name, err }) catch {};
            continue;
        };
        std.fmt.format(display.writer(), "{s} passed\n", .{t.name}) catch {};
    }
    hang();
}

/// Kernel main
export fn kernel_main() noreturn {

    // Zero out bss
    const bss_length: usize = @intFromPtr(__bss_end) - @intFromPtr(__bss);
    var i: usize = 0;
    while (i < bss_length) : (i += 1) __bss[i] = 0;

    if (builtin.is_test) {
        test_main();
    }

    // Print hello world
    _ = sbi.sbi_putstr("\n\nHello World\n\n");
    // _ = common.format_print("{d} + {d} = {d}", .{ 9, 10, 19 }) catch {
    //     _ = sbi.sbi_putstr("printf err");
    // };

    // var x: u8 = 255;
    // x = x + 1;

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

test "always succeeds" {
    try expect(true);
}

test "always fails" {
    try expect(false);
}
