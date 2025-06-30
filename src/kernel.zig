const std = @import("std");

const builtin = @import("builtin");

const sbi = @import("sbi.zig");
const common = @import("common.zig");
const debug = @import("debug.zig");
const testing = @import("testing.zig");
const riscv64 = @import("riscv64.zig");
const alloc = @import("alloc.zig");

pub const std_options: std.Options = .{
    .page_size_min = 4096,
    .page_size_max = 4 * 1024,
    .log_level = .debug,
    .logFn = logFn,
};

pub fn logFn(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime format: []const u8, args: anytype) void {
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ @tagName(scope) ++ " ";

    // Print message
    common.format_print(prefix ++ format ++ "\n", args);
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

var display = common.UARTDisplay{};

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

    debug_info.printStackTrace(display.writer(), ra orelse @returnAddress(), @frameAddress()) catch |err| {
        std.log.err("panic: stacktrace err = {}", .{err});
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

    alloc.init();
    std.log.debug("{*}", .{alloc.get_alloc_start()});
    const one_page = alloc.alloc_page(1) catch {
        unreachable;
    };
    const ten_page = alloc.alloc_page(10) catch {
        unreachable;
    };
    alloc.print_page_allocations();

    std.log.info("De allocating one page {*}", .{one_page});
    alloc.free_page(one_page);
    std.log.info("De allocating ten pages {*}", .{ten_page});

    alloc.free_page(ten_page);
    alloc.print_page_allocations();
    // Register exception handler
    riscv64.write_csr(riscv64.ControlStatusRegister.stvec, @intFromPtr(&riscv64.exception_entry));

    asm volatile ("unimp");

    if (builtin.is_test) {
        testing.main();
    }

    // Print hello world
    common.putstr("\n\nHello World\n\n");

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
