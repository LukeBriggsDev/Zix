pub const num_callee_saved_regs = 13;

/// A wrapper function to call `riscv_switch_context` via naked calling convention with parameters.
/// Stack corruption occurs without this an context switching fails.
pub fn switch_context(prev_sp: **usize, next_sp: **usize) void {
    asm volatile (
        \\call riscv_switch_context
        :
        : [prev_sp] "{a0}" (prev_sp),
          [next_sp] "{a1}" (next_sp),
    );
}

/// Switch context by pushing registers to the stack
/// then popping them off the next process's stack
export fn riscv_switch_context() callconv(.Naked) void {
    asm volatile (
    // Save callee-saved registers onto the current process's stack.
    // Move stack to store contents of the 12 callee registers + ra (8 bytes each)
        \\addi sp, sp, -13 * 8
        \\sd ra, 0 * 8(sp)
        \\sd s0, 1 * 8(sp)
        \\sd s1, 2 * 8(sp)
        \\sd s2, 3 * 8(sp)
        \\sd s3, 4 * 8(sp)
        \\sd s4, 5 * 8(sp)
        \\sd s5, 6 * 8(sp)
        \\sd s6, 7 * 8(sp)
        \\sd s7, 8 * 8(sp)
        \\sd s8, 9 * 8(sp)
        \\sd s9, 10 * 8(sp)
        \\sd s10, 11 * 8(sp)
        \\sd s11, 12 * 8(sp)

        // Switch the stack pointer
        \\sd sp, (a0)
        \\ld sp, (a1)

        // Restore callee saved registers from the next process's stack
        \\ld ra, 0 * 8(sp)
        \\ld s0, 1 * 8(sp)
        \\ld s1, 2 * 8(sp)
        \\ld s2, 3 * 8(sp)
        \\ld s3, 4 * 8(sp)
        \\ld s4, 5 * 8(sp)
        \\ld s5, 6 * 8(sp)
        \\ld s6, 7 * 8(sp)
        \\ld s7, 8 * 8(sp)
        \\ld s8, 9 * 8(sp)
        \\ld s9, 10 * 8(sp)
        \\ld s10, 11 * 8(sp)
        \\ld s11, 12 * 8(sp)
        // Pop the registers from the stack
        \\addi sp, sp, 13 * 8
        \\ret
    );
}
