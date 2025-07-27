//! Root of arch module, provides structs to interface with architecture-level methods
const builtin = @import("builtin");
const std = @import("std");

/// Arch structure containing generic fields that architectures should expose
pub const Arch = struct {
    /// Writer to print to a stdout terminal
    writer: std.io.AnyWriter,
    /// Architecture initialization (exception handling, etc)
    init: *const fn () void,
    /// Shutdown method
    shutdown: *const fn () noreturn,
    /// Number of callee saved registers
    num_callee_saved_regs: usize,
    /// Switch context between processes
    switch_context: *const fn (prev_sp: **usize, next_sp: **usize) void,
};

/// Instance containing the Arch methods of the current architecture
pub const internals: Arch = switch (builtin.cpu.arch) {
    .riscv64 => @import("riscv64/arch.zig").arch,
    else => unreachable,
};
