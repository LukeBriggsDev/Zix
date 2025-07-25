//! Defines main test boot stub and method as well as the test runner

const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");
const debug = @import("debug.zig");

// Import dependencies as root when they are the current module
const io = @import("io");
const arch = @import("arch");

const log = std.log;

const __stack_top = @extern([*]u8, .{
    .name = "__bss_end",
});

pub const std_options: std.Options = .{
    .page_size_min = 4096,
    .page_size_max = 4 * 1024,
    .log_level = .info,
    .logFn = logFn,
};

var debug_allocator_bytes: [16 * 1024 * 1024]u8 = undefined; // 16 MB

pub fn logFn(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime format: []const u8, args: anytype) void {
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ "<" ++ @tagName(scope) ++ "> ";

    // Print message
    std.fmt.format(io.TTY.writer, prefix ++ format ++ "\n", args) catch {};
}

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, ra: ?usize) noreturn {
    _ = stack_trace;
    std.log.err("\n!!!!!!!!!!!!\nKERNEL PANIC\n!!!!!!!!!!!!", .{});
    std.log.err("panic: {s}\n", .{message});

    var debug_allocator = std.heap.FixedBufferAllocator.init(&debug_allocator_bytes);

    var debug_info = debug.DebugInfo.init(debug_allocator.allocator(), .{}) catch |err| {
        std.log.err("panic: debug info err = {}", .{err});
        while (true) {}
    };

    defer debug_info.deinit();

    debug_info.printStackTrace(io.TTY.writer, ra orelse @returnAddress(), @frameAddress()) catch |err| {
        std.log.err("panic: stacktrace err = {}", .{err});
    };

    while (true) {}
}

export fn tmain() noreturn {
    // Init architecture
    arch.internals.init();
    log.info("Starting tests...", .{});
    const test_functions = builtin.test_functions;
    log.info("Found {} tests", .{test_functions.len});
    for (test_functions) |t| {
        t.func() catch |err| {
            log.err("{s} fail: {}", .{ t.name, err });
            continue;
        };
        log.info("{s} passed", .{t.name});
    }
    log.info("Finished tests.", .{});
    arch.internals.shutdown();
}

export fn boot() linksection(".text.boot") callconv(.Naked) noreturn {
    asm volatile (
        \\mv sp, %[stack_top] // Set the stack pointer
        \\j tmain
        :
        : [stack_top] "r" (__stack_top), // Pass the stack top address as %[stack_top]
    );
}

test {
    std.testing.refAllDecls(@This());
}
