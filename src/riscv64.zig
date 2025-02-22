const std = @import("std");
const common = @import("common.zig");

pub const ControlStatusRegister = enum {
    sstatus,
    sedeleg,
    sideleg,
    sie,
    stvec,
    scounteren,
    sscratch,
    sepc,
    scause,
    stval,
    sip,
    satp,
};

pub fn write_csr(comptime reg: ControlStatusRegister, value: usize) void {
    const asm_str = std.fmt.comptimePrint("csrw {s}, %[value]", .{@tagName(reg)});
    asm volatile (asm_str
        :
        : [value] "r" (value),
    );
}

pub fn read_csr(comptime reg: ControlStatusRegister) usize {
    var val: usize = undefined;
    const asm_str = std.fmt.comptimePrint("csrr %[val], {s}", .{@tagName(reg)});
    asm volatile (asm_str
        : [val] "=r" (val),
    );
    return val;
}

const TrapFrame = packed struct {
    ra: u64,
    sp: u64,
    gp: u64,
    tp: u64,
    t0: u64,
    t1: u64,
    t2: u64,
    s0: u64,
    s1: u64,
    a0: u64,
    a1: u64,
    a2: u64,
    a3: u64,
    a4: u64,
    a5: u64,
    a6: u64,
    a7: u64,
    s2: u64,
    s3: u64,
    s4: u64,
    s5: u64,
    s6: u64,
    s7: u64,
    s8: u64,
    s9: u64,
    s10: u64,
    s11: u64,
    t3: u64,
    t4: u64,
    t5: u64,
    t6: u64,
};

/// Exception entry
/// Store all the registers, handle trap, then load back the registers
pub fn exception_entry() align(8) callconv(.Naked) void {
    asm volatile (
    // Store sp in scratch register
        \\csrw sscratch, sp
        // Move stack to store contents of 31 registers (8 bytes each)
        \\addi sp, sp, -8 * 31
        // Load all registers
        \\sd x1, 8 * 0(sp)
        \\sd x2, 8 * 1(sp)
        \\sd x3, 8 * 2(sp)
        \\sd x4, 8 * 3(sp)
        \\sd x5, 8 * 4(sp)
        \\sd x6, 8 * 5(sp)
        \\sd x7, 8 * 6(sp)
        \\sd x8, 8 * 7(sp)
        \\sd x9, 8 * 8(sp)
        \\sd x10, 8 * 9(sp)
        \\sd x11, 8 * 10(sp)
        \\sd x12, 8 * 11(sp)
        \\sd x13, 8 * 12(sp)
        \\sd x14, 8 * 13(sp)
        \\sd x15, 8 * 14(sp)
        \\sd x16, 8 * 15(sp)
        \\sd x17, 8 * 16(sp)
        \\sd x18, 8 * 17(sp)
        \\sd x19, 8 * 18(sp)
        \\sd x20, 8 * 19(sp)
        \\sd x21, 8 * 20(sp)
        \\sd x22, 8 * 21(sp)
        \\sd x23, 8 * 22(sp)
        \\sd x24, 8 * 23(sp)
        \\sd x25, 8 * 24(sp)
        \\sd x26, 8 * 25(sp)
        \\sd x27, 8 * 26(sp)
        \\sd x28, 8 * 27(sp)
        \\sd x29, 8 * 28(sp)
        \\sd x30, 8 * 29(sp)
        \\sd x31, 8 * 30(sp)
        // Deal with sp
        // Read initial sp into func arg 0
        \\csrr a0, sscratch
        // Store sp on stack
        \\sd a0, 8 * 31(sp) 
        // Call handler
        // Move stack pointer to first argument
        \\mv a0, sp
        \\call handle_trap
        // Load back regisers
        // Load all registers
        \\ld x1, 8 * 0(sp)
        \\ld x2, 8 * 1(sp)
        \\ld x3, 8 * 2(sp)
        \\ld x4, 8 * 3(sp)
        \\ld x5, 8 * 4(sp)
        \\ld x6, 8 * 5(sp)
        \\ld x7, 8 * 6(sp)
        \\ld x8, 8 * 7(sp)
        \\ld x9, 8 * 8(sp)
        \\ld x10, 8 * 9(sp)
        \\ld x11, 8 * 10(sp)
        \\ld x12, 8 * 11(sp)
        \\ld x13, 8 * 12(sp)
        \\ld x14, 8 * 13(sp)
        \\ld x15, 8 * 14(sp)
        \\ld x16, 8 * 15(sp)
        \\ld x17, 8 * 16(sp)
        \\ld x18, 8 * 17(sp)
        \\ld x19, 8 * 18(sp)
        \\ld x20, 8 * 19(sp)
        \\ld x21, 8 * 20(sp)
        \\ld x22, 8 * 21(sp)
        \\ld x23, 8 * 22(sp)
        \\ld x24, 8 * 23(sp)
        \\ld x25, 8 * 24(sp)
        \\ld x26, 8 * 25(sp)
        \\ld x27, 8 * 26(sp)
        \\ld x28, 8 * 27(sp)
        \\ld x29, 8 * 28(sp)
        \\ld x30, 8 * 29(sp)
        \\ld x31, 8 * 30(sp)
        // Load stack pointer
        \\ld sp, 8 * 31(sp)
        \\sret
        :
        : [handle_trap] "r" (&handle_trap),
    );
}

export fn handle_trap(frame: *TrapFrame) noreturn {
    _ = frame;
    const scause = read_csr(ControlStatusRegister.scause);
    const stval = read_csr(ControlStatusRegister.stval);
    const sepc = read_csr(ControlStatusRegister.sepc);
    common.format_print("Unexpected trap: scause = {x}, stval = {x}, sepc = {x}\n", .{ scause, stval, sepc }) catch {};
    while (true) {}
}
