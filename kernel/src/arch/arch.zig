//! Root of arch module, provides structs to interface with architecture-level methods
const builtin = @import("builtin");
const std = @import("std");

/// Instance containing the Arch methods of the current architecture
pub const internals: Arch = switch (builtin.cpu.arch) {
    .riscv64 => @import("riscv64/arch.zig").arch,
    else => unreachable,
};
pub const SyscallHandler = *const fn (no: usize, args: [6]usize) usize;

/// Arch structure containing generic fields that architectures should expose
pub const Arch = struct {
    /// Writer to print to a serial terminal
    writer: *std.Io.Writer,
    /// Reader to read from a serial terminal
    try_read_byte: *const fn () ?u8,
    /// Architecture initialization (exception handling, etc)
    init: *const fn () void,
    /// Shutdown method
    shutdown: *const fn () noreturn,
    /// Number of callee saved registers
    num_callee_saved_regs: usize,
    /// Switch context between processes
    switch_context: *const fn (prev_sp: **usize, next_sp: **usize) void,
    /// Entry trampoline for new processes: calls the entry stored in s0, then process_exit
    process_start: *const fn () callconv(.naked) noreturn,
    /// Page mapping function
    map_page: *const fn (
        allocator: std.mem.Allocator,
        root_table: []usize,
        vaddr: usize,
        paddr: usize,
        flags: usize,
    ) void,
    set_syscall_handler: *const fn (h: SyscallHandler) void,
};
