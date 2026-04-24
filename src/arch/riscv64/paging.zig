/// Implementation for SV39 paging
const std = @import("std");
const builtin = @import("builtin");
const mem = @import("mem");

// satp mode for sv39
const satp_sv39 = 8 << 60;

/// SV39 Page Table Entry:
///
/// +----------+--------+--------+--------+-----+-+-+-+-+-+-+-+-+
/// | Reserved | PPN[2] | PPN[1] | PPN[0] | RSW |D|A|G|U|X|W|R|V|
/// +----------+--------+--------+--------+-----+-+-+-+-+-+-+-+-+
/// |    10    |   26   |   9    |   9    |  2  |1|1|1|1|1|1|1|1|
/// +----------+--------+--------+--------+-----+-+-+-+-+-+-+-+-+
const PageEntry = packed struct {
    valid: bool,
    read: bool,
    write: bool,
    execute: bool,
    user: bool,
    global: u1,
    accessed: u1,
    dirty: u1,
    other: u2,
    ppn: PPN,
    reserved: u10,
};

const PPN = packed struct {
    ppn0: u9,
    ppn1: u9,
    ppn2: u26,
};

/// SV39 Virtual Address:
///
/// +--------+--------+--------+--------+
/// | VPN[2] | VPN[1] | VPN[0] | Offset |
/// +--------+--------+--------+--------+
/// |   9    |   9    |   9    |   12   |
/// +--------+--------+--------+--------+
///
const VirtualAddress = packed struct {
    offset: u12,
    vpn0: u9,
    vpn1: u9,
    vpn2: u9,
};

pub fn map_page(allocator: std.mem.Allocator, root_table: []usize, vaddr: usize, paddr: usize, flags: usize) void {
    const flags_entry: PageEntry = @bitCast(flags);
    var table2: [*]PageEntry = @ptrCast(root_table);

    if (vaddr % std.heap.pageSize() != 0) {
        std.debug.panic("Unaligned vaddr 0x{x}", .{vaddr});
    }

    if (paddr % std.heap.pageSize() != 0) {
        std.debug.panic("Unaligned paddr 0x{x}", .{paddr});
    }

    // Make sure R, W, or X have been provided
    if (!flags_entry.read and !flags_entry.write and !flags_entry.execute) {
        std.debug.panic("Neither Read, Write, nor Execute flags set!", .{});
    }

    const vaddr_u39: u39 = @intCast(vaddr);
    const virtual_addr: VirtualAddress = @bitCast(vaddr_u39);

    // Walk the page table: vpn[2] -> vpn[1] -> vpn[0]
    var v = &table2[virtual_addr.vpn2];

    const levels = [_]u9{ virtual_addr.vpn1, virtual_addr.vpn0 };
    for (levels) |vpn| {
        if (!v.valid) {
            // Allocate a zeroed page for the next-level table
            const new_page = allocator.alloc(u64, std.heap.pageSize() / @sizeOf(u64)) catch |err| {
                std.debug.panic("Out of memory! Cannot map page! {}", .{err});
            };
            @memset(std.mem.sliceAsBytes(new_page), 0);
            // Write the parent entry to point at the new table (non-leaf: R=W=X=0)
            const new_ppn: u44 = @intCast(@intFromPtr(new_page.ptr) / std.heap.pageSize());
            v.* = std.mem.zeroes(PageEntry);
            v.valid = true;
            v.ppn = @bitCast(new_ppn);
        }
        // Descend into the next-level table
        const child_ppn: u44 = @bitCast(v.ppn);
        const next_table: [*]PageEntry = @ptrFromInt(@as(usize, child_ppn) << 12);
        v = &next_table[vpn];
    }

    // v now points at the leaf entry in the level-0 table
    var new_entry = flags_entry;
    new_entry.valid = true;
    const new_ppn: u44 = @intCast(paddr / std.heap.pageSize());
    new_entry.ppn = @bitCast(new_ppn);
    v.* = new_entry;
}

test "Virtual to Physical address map" {
    std.debug.assert(true);
}
