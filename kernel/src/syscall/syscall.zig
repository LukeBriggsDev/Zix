//! System Call behaviour
const std = @import("std");
const arch = @import("arch");
const proc = @import("proc");

/// Syscall numbers
pub const Number = enum(usize) {
    putchar = 1,
    getchar = 2,
    _,
};

/// Set architecture syscall handler to `handle`
pub fn init() void {
    arch.internals.set_syscall_handler(&handle);
}

/// Syscall handler, dispatches syscalls to the given implentation
fn handle(no: usize, args: [6]usize) usize {
    return switch (@as(Number, @enumFromInt(no))) {
        .putchar => sys_putchar(@intCast(args[0])),
        .getchar => sys_getchar(),
        else => @panic("Unexpected syscall"),
    };
}

/// Write a character to serial port
fn sys_putchar(c: usize) usize {
    arch.internals.writer.writeByte(@intCast(c)) catch return std.math.maxInt(usize);
    return 0;
}

/// Read a character from serial port
fn sys_getchar() usize {
    while (true) {
        if (arch.internals.try_read_byte()) |c| return c;
        proc.yield();
    }
}
