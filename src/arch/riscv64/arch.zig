//! RISCV64 architecture methods

const RV64TTY = @import("tty.zig").RV64TTY;
const csr = @import("csr.zig");
const Arch = @import("../arch.zig").Arch;
const sbi = @import("sbi.zig");
const process = @import("process.zig");

var tty = RV64TTY{};

/// RISCV64 implementation of Arch
pub const arch = Arch{
    .writer = tty.writer().any(),
    .init = init,
    .shutdown = sbi.sbi_shutdown,
    .num_callee_saved_regs = process.num_callee_saved_regs,
    .switch_context = process.switch_context,
};

pub fn init() void {
    csr.init();
}
