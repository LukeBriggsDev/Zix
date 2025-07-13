const std = @import("std");

const builtin = @import("builtin");
const arch = @import("arch").internals;
const io = @import("io");
const debug = @import("debug.zig");
pub const mem = @import("mem");
const testing = @import("testing.zig");

pub const std_options: std.Options = .{
    .page_size_min = 4096,
    .page_size_max = 4 * 1024,
    .log_level = .debug,
    .logFn = logFn,
};

pub fn logFn(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime format: []const u8, args: anytype) void {
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ "<" ++ @tagName(scope) ++ "> ";

    // Print message
    std.fmt.format(io.TTY.writer, prefix ++ format ++ "\n", args) catch {};
}

const __bss = @extern([*]u8, .{
    .name = "__bss",
});

const __bss_end = @extern([*]u8, .{
    .name = "__bss_end",
});

const __stack_top = @extern([*]u8, .{
    .name = "__bss_end",
});

var debug_allocator_bytes: [16 * 1024 * 1024]u8 = undefined; // 16 MB

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, ra: ?usize) noreturn {
    _ = stack_trace;
    std.log.err("\n!!!!!!!!!!!!\nKERNEL PANIC\n!!!!!!!!!!!!", .{});
    std.log.err("panic: {s}\n", .{message});

    var debug_allocator = std.heap.FixedBufferAllocator.init(&debug_allocator_bytes);

    var debug_info = debug.DebugInfo.init(debug_allocator.allocator(), .{}) catch |err| {
        std.log.err("panic: debug info err = {}", .{err});
        hang();
    };

    defer debug_info.deinit();

    debug_info.printStackTrace(io.TTY.writer, ra orelse @returnAddress(), @frameAddress()) catch |err| {
        std.log.err("panic: stacktrace err = {}", .{err});
    };

    hang();
}

fn hang() noreturn {
    while (true) {}
}

/// Kernel main
export fn kmain() noreturn {

    // Zero out bss
    const bss_length: usize = @intFromPtr(__bss_end) - @intFromPtr(__bss);
    var i: usize = 0;
    while (i < bss_length) : (i += 1) __bss[i] = 0;

    // Initialize architecture
    arch.init();

    // Initialize Allocator
    mem.initKernelPageAllocator();

    const allocator = mem.kernel_page_allocator;

    const my_arr = allocator.alloc(u8, 5) catch {
        unreachable;
    };

    my_arr[0] = 1;

    arch.shutdown();
}

/// Main entry point for the kernel from the SBI
export fn boot() linksection(".text.boot") callconv(.Naked) noreturn {
    asm volatile (
        \\mv sp, %[stack_top] // Set the stack pointer
        \\j kmain
        :
        : [stack_top] "r" (__stack_top), // Pass the stack top address as %[stack_top]
    );
}
