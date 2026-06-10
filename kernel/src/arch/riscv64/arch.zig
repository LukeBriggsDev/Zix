//! RISCV64 architecture methods

const tty = @import("tty.zig");
const csr = @import("csr.zig");
const Arch = @import("../arch.zig").Arch;
const sbi = @import("sbi.zig");
const process = @import("process.zig");
const paging = @import("paging.zig");

/// RISCV64 implementation of Arch
pub const arch = Arch{
    .writer = &tty.writer_instance,
    .init = init,
    .shutdown = sbi.sbi_shutdown,
    .num_callee_saved_regs = process.num_callee_saved_regs,
    .switch_context = process.switch_context,
    .process_start = process.riscv_process_start,
    .map_page = paging.map_page,
};

pub fn init() void {
    csr.init();
}
