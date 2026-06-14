const std = @import("std");
const builtin = @import("builtin");
const DW = std.dwarf;
const io = @import("io");

const source_files: []const []const u8 = &.{
    "arch/arch.zig",
    "arch/riscv64/arch.zig",
    "arch/riscv64/csr.zig",
    "arch/riscv64/sbi.zig",
    "arch/riscv64/tty.zig",
    "arch/riscv64/paging.zig",
    "debug.zig",
    "io/io.zig",
    "io/tty.zig",
    "kernel.zig",
    "testing.zig",
    "mem/KernelPageAllocator.zig",
    "mem/mem.zig",
    "proc/process.zig",
};

pub const DebugInfo = @This();

pub const Symbols = struct {
    debug_info: [2]@EnumLiteral() = [_]@EnumLiteral(){ .@".debug_info_start", .@".debug_info_end" },
    debug_abbrev: [2]@EnumLiteral() = [_]@EnumLiteral(){ .@".debug_abbrev_start", .@".debug_abbrev_end" },
    debug_str: [2]@EnumLiteral() = [_]@EnumLiteral(){ .@".debug_str_start", .@".debug_str_end" },
    debug_line: [2]@EnumLiteral() = [_]@EnumLiteral(){ .@".debug_line_start", .@".debug_line_end" },
    debug_ranges: [2]@EnumLiteral() = [_]@EnumLiteral(){ .@".debug_ranges_start", .@".debug_ranges_end" },

    pub fn section(self: @This(), comptime symbol: std.meta.FieldEnum(@This())) []const u8 {
        const start_addr = addressOf(@field(self, @tagName(symbol))[0]);
        const end_addr = addressOf(@field(self, @tagName(symbol))[1]);
        const sgmt: [*]const u8 = @ptrFromInt(start_addr);
        return sgmt[0 .. end_addr - start_addr];
    }

    pub fn startVA(self: @This(), comptime symbol: std.meta.FieldEnum(@This())) usize {
        return addressOf(@field(self, @tagName(symbol))[0]);
    }

    fn addressOf(symbol: @EnumLiteral()) usize {
        return @intFromPtr(@extern(*anyopaque, .{ .name = @tagName(symbol) }));
    }
};

allocator: std.mem.Allocator,
dwarf: std.debug.Dwarf,
patched_debug_info: []u8,

const endian = builtin.target.cpu.arch.endian();

// ── Minimal LEB128 helpers ────────────────────────────────────────────────────

fn readUleb128(data: []const u8, pos: *usize) u64 {
    var result: u64 = 0;
    var shift: u6 = 0;
    while (pos.* < data.len) {
        const byte = data[pos.*];
        pos.* += 1;
        result |= @as(u64, byte & 0x7f) << shift;
        if (byte & 0x80 == 0) return result;
        shift +|= 7;
    }
    return result;
}

fn skipSleb128(data: []const u8, pos: *usize) void {
    while (pos.* < data.len) {
        const byte = data[pos.*];
        pos.* += 1;
        if (byte & 0x80 == 0) return;
    }
}

// ── Attribute value skip/patch ────────────────────────────────────────────────

/// Skip or patch one attribute value in `data` at `*pos`.
/// When a patchable form is encountered, subtracts the appropriate section start VA.
fn processAttrValue(
    at_id: u64,
    form: u64,
    fmt_size: usize, // 4 for 32-bit DWARF, 8 for 64-bit DWARF
    addr_size: u8,
    data: []u8,
    pos: *usize,
    str_start_va: usize,
    line_start_va: usize,
    ranges_start_va: usize,
) void {
    switch (form) {
        // Forms that reference other sections — patch to section-relative
        DW.FORM.strp => {
            patchSectionRef(data, pos, fmt_size, str_start_va);
        },
        DW.FORM.line_strp => {
            // .debug_line_str — not needed for basic stack traces; just skip
            pos.* += fmt_size;
        },
        DW.FORM.sec_offset => {
            const sub: ?usize = switch (at_id) {
                DW.AT.stmt_list => line_start_va,
                DW.AT.ranges => ranges_start_va,
                else => null,
            };
            if (sub) |s| {
                patchSectionRef(data, pos, fmt_size, s);
            } else {
                pos.* += fmt_size;
            }
        },

        // Fixed-size forms — just skip
        DW.FORM.addr => pos.* += addr_size,
        DW.FORM.data1, DW.FORM.flag, DW.FORM.ref1 => pos.* += 1,
        DW.FORM.data2, DW.FORM.ref2 => pos.* += 2,
        DW.FORM.data4, DW.FORM.ref4, DW.FORM.ref_sup4 => pos.* += 4,
        DW.FORM.data8, DW.FORM.ref8, DW.FORM.ref_sig8, DW.FORM.ref_sup8 => pos.* += 8,
        DW.FORM.data16 => pos.* += 16,
        DW.FORM.ref_addr => pos.* += fmt_size,

        // Variable-size forms
        DW.FORM.string => {
            while (pos.* < data.len and data[pos.*] != 0) pos.* += 1;
            pos.* += 1;
        },
        DW.FORM.block1 => {
            const len = data[pos.*];
            pos.* += 1 + len;
        },
        DW.FORM.block2 => {
            const len = std.mem.readInt(u16, data[pos.*..][0..2], endian);
            pos.* += 2 + len;
        },
        DW.FORM.block4 => {
            const len = std.mem.readInt(u32, data[pos.*..][0..4], endian);
            pos.* += 4 + len;
        },
        DW.FORM.block, DW.FORM.exprloc => {
            const len = readUleb128(data, pos);
            pos.* += @intCast(len);
        },
        DW.FORM.sdata => skipSleb128(data, pos),
        DW.FORM.udata, DW.FORM.ref_udata => _ = readUleb128(data, pos),

        DW.FORM.flag_present, DW.FORM.implicit_const => {},

        // DWARF5 indirect string forms — section-relative by spec, no patch needed
        DW.FORM.strx, DW.FORM.addrx, DW.FORM.loclistx, DW.FORM.rnglistx => _ = readUleb128(data, pos),
        DW.FORM.strx1, DW.FORM.addrx1 => pos.* += 1,
        DW.FORM.strx2, DW.FORM.addrx2 => pos.* += 2,
        DW.FORM.strx3, DW.FORM.addrx3 => pos.* += 3,
        DW.FORM.strx4, DW.FORM.addrx4 => pos.* += 4,

        else => {},
    }
}

fn patchSectionRef(data: []u8, pos: *usize, fmt_size: usize, subtract: usize) void {
    if (fmt_size == 4) {
        const abs = std.mem.readInt(u32, data[pos.*..][0..4], endian);
        std.mem.writeInt(u32, data[pos.*..][0..4], abs -% @as(u32, @truncate(subtract)), endian);
    } else {
        const abs = std.mem.readInt(u64, data[pos.*..][0..8], endian);
        std.mem.writeInt(u64, data[pos.*..][0..8], abs -% subtract, endian);
    }
    pos.* += fmt_size;
}

// ── Abbreviation table walker ─────────────────────────────────────────────────

/// Find `code` in the abbreviation table starting at `abbrev_data[table_start..]` and
/// process all its attribute values in `debug_info` at `*pos`.
fn walkDieAttrs(
    code: u64,
    abbrev_data: []const u8,
    table_start: usize,
    fmt_size: usize,
    addr_size: u8,
    debug_info: []u8,
    pos: *usize,
    str_start_va: usize,
    line_start_va: usize,
    ranges_start_va: usize,
) void {
    var ap: usize = table_start;

    while (ap < abbrev_data.len) {
        const abbrev_code = readUleb128(abbrev_data, &ap);
        if (abbrev_code == 0) break;
        _ = readUleb128(abbrev_data, &ap); // tag
        ap += 1; // has_children byte

        const is_match = (abbrev_code == code);
        while (true) {
            const at_id = readUleb128(abbrev_data, &ap);
            const form_id = readUleb128(abbrev_data, &ap);
            if (at_id == 0 and form_id == 0) break;

            if (form_id == DW.FORM.implicit_const) {
                skipSleb128(abbrev_data, &ap);
                continue;
            }

            if (is_match) {
                processAttrValue(at_id, form_id, fmt_size, addr_size, debug_info, pos, str_start_va, line_start_va, ranges_start_va);
            }
        }

        if (is_match) return;
    }
}

// ── Main patcher ──────────────────────────────────────────────────────────────

/// Copy debug_info and rewrite all cross-section byte offsets from absolute VAs to
/// section-relative. LLD patches these to absolute VAs when sections live in PT_LOAD
/// segments; std.debug.Dwarf expects section-relative offsets.
pub fn patchDebugInfo(
    allocator: std.mem.Allocator,
    data: []const u8,
    abbrev_data: []const u8,
    abbrev_start_va: usize,
    str_start_va: usize,
    line_start_va: usize,
    ranges_start_va: usize,
) ![]u8 {
    const patched = try allocator.dupe(u8, data);
    errdefer allocator.free(patched);

    var pos: usize = 0;
    while (pos < patched.len) {
        const cu_start = pos;
        if (pos + 4 > patched.len) break;

        const first_word = std.mem.readInt(u32, patched[pos..][0..4], endian);
        const is_64bit = (first_word == 0xffff_ffff);
        const len_field_size: usize = if (is_64bit) 12 else 4;
        const fmt_size: usize = if (is_64bit) 8 else 4;

        const unit_length: u64 = blk: {
            if (is_64bit) {
                if (pos + 12 > patched.len) break;
                break :blk std.mem.readInt(u64, patched[pos + 4 ..][0..8], endian);
            } else break :blk first_word;
        };
        if (unit_length == 0) break;

        pos += len_field_size;
        if (pos + 2 > patched.len) break;

        const version = std.mem.readInt(u16, patched[pos..][0..2], endian);
        pos += 2;

        var addr_size: u8 = undefined;
        var abbrev_table_start: usize = undefined;

        if (version >= 5) {
            if (pos + 2 + fmt_size > patched.len) break;
            pos += 1; // unit_type
            addr_size = patched[pos];
            pos += 1;
            abbrev_table_start = patchAndReadRef(patched, &pos, fmt_size, abbrev_start_va);
        } else {
            if (pos + fmt_size + 1 > patched.len) break;
            abbrev_table_start = patchAndReadRef(patched, &pos, fmt_size, abbrev_start_va);
            addr_size = patched[pos];
            pos += 1;
        }

        // Walk all DIEs in this CU, patching cross-section references
        const dies_end = cu_start + len_field_size + @as(usize, unit_length);
        var die_pos = pos;
        while (die_pos < dies_end and die_pos < patched.len) {
            const code = readUleb128(patched, &die_pos);
            if (code == 0) continue; // null DIE (end-of-sibling-list marker)
            walkDieAttrs(code, abbrev_data, abbrev_table_start, fmt_size, addr_size, patched, &die_pos, str_start_va, line_start_va, ranges_start_va);
        }

        pos = dies_end;
    }

    return patched;
}

fn patchAndReadRef(data: []u8, pos: *usize, fmt_size: usize, subtract: usize) usize {
    if (fmt_size == 4) {
        const abs = std.mem.readInt(u32, data[pos.*..][0..4], endian);
        const rel = abs -% @as(u32, @truncate(subtract));
        std.mem.writeInt(u32, data[pos.*..][0..4], rel, endian);
        pos.* += 4;
        return rel;
    } else {
        const abs = std.mem.readInt(u64, data[pos.*..][0..8], endian);
        const rel = abs -% subtract;
        std.mem.writeInt(u64, data[pos.*..][0..8], rel, endian);
        pos.* += 8;
        return @intCast(rel);
    }
}

// ── Public API ────────────────────────────────────────────────────────────────

pub fn init(allocator: std.mem.Allocator, symbols: Symbols) !DebugInfo {
    const Sid = std.debug.Dwarf.Section.Id;

    const info_data = symbols.section(.debug_info);
    const abbrev_data = symbols.section(.debug_abbrev);
    const str_data = symbols.section(.debug_str);
    const line_data = symbols.section(.debug_line);
    const ranges_data = symbols.section(.debug_ranges);


    const patched_info = try patchDebugInfo(
        allocator,
        info_data,
        abbrev_data,
        symbols.startVA(.debug_abbrev),
        symbols.startVA(.debug_str),
        symbols.startVA(.debug_line),
        symbols.startVA(.debug_ranges),
    );
    errdefer allocator.free(patched_info);

    var sections: std.debug.Dwarf.SectionArray = @splat(null);
    sections[@intFromEnum(Sid.debug_info)] = .{ .data = patched_info, .owned = false };
    sections[@intFromEnum(Sid.debug_abbrev)] = .{ .data = abbrev_data, .owned = false };
    sections[@intFromEnum(Sid.debug_str)] = .{ .data = str_data, .owned = false };
    sections[@intFromEnum(Sid.debug_line)] = .{ .data = line_data, .owned = false };
    sections[@intFromEnum(Sid.debug_ranges)] = .{ .data = ranges_data, .owned = false };

    var dwarf: std.debug.Dwarf = .{ .sections = sections };
    try dwarf.open(allocator, endian);

    return .{ .allocator = allocator, .dwarf = dwarf, .patched_debug_info = patched_info };
}

pub fn deinit(self: *DebugInfo) void {
    self.dwarf.deinit(self.allocator);
    self.allocator.free(self.patched_debug_info);
    self.* = undefined;
}

// ── Stack trace printing ──────────────────────────────────────────────────────

const FrameIterator = struct {
    ra: usize,
    fp: usize,
    first: bool = true,

    fn init(return_address: usize, frame_address: usize) @This() {
        return .{ .ra = return_address, .fp = frame_address };
    }

    fn next(self: *@This()) ?usize {
        if (self.first) {
            self.first = false;
            return self.ra;
        }
        if (self.fp < 16) return null;
        const saved_ra = @as(*const usize, @ptrFromInt(self.fp - @sizeOf(usize))).*;
        const saved_fp = @as(*const usize, @ptrFromInt(self.fp - 2 * @sizeOf(usize))).*;
        if (saved_ra == 0 or saved_fp == 0 or saved_fp <= self.fp) return null;
        self.ra = saved_ra;
        self.fp = saved_fp;
        return saved_ra;
    }
};

pub fn printStackTrace(self: *DebugInfo, writer: anytype, return_address: usize, frame_address: usize) !void {
    var it = FrameIterator.init(return_address, frame_address);
    while (it.next()) |address| {
        const sym_name = self.dwarf.getSymbolName(address) orelse "???";

        const cu = self.dwarf.findCompileUnit(endian, address) catch {
            try printLineInfo(writer, null, address, sym_name, "???");
            continue;
        };

        if (cu.src_loc_cache == null) {
            self.dwarf.populateSrcLocCache(self.allocator, endian, cu) catch {
                try printLineInfo(writer, null, address, sym_name, "???");
                continue;
            };
        }

        const cu_name = cu.die.getAttrString(&self.dwarf, endian, DW.AT.name, self.dwarf.section(.debug_str), cu) catch "???";

        const src_loc: ?std.debug.SourceLocation = blk: {
            const cache = &cu.src_loc_cache.?;
            const le = cache.findSource(address) catch break :blk null;
            if (le.isInvalid()) break :blk null;
            if (cache.version < 5 and le.file == 0) break :blk null;
            const file_idx = le.file - @intFromBool(cache.version < 5);
            if (file_idx >= cache.files.len) break :blk null;
            break :blk .{
                .file_name = cache.files[file_idx].path,
                .line = le.line,
                .column = le.column,
            };
        };

        try printLineInfo(writer, src_loc, address, sym_name, cu_name);
    }
}

fn printLineFromBuffer(out_stream: anytype, contents: []const u8, line_info: std.debug.SourceLocation) anyerror!void {
    var line: usize = 1;
    var column: usize = 1;
    for (contents) |byte| {
        if (line == line_info.line) {
            try out_stream.writeByte(byte);
            if (byte == '\n') {
                var i: usize = 1;
                while (i != line_info.column) : (i += 1) {
                    try out_stream.writeByte(' ');
                }
                try out_stream.writeAll("^\n");
                return;
            }
        }
        if (byte == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return error.EndOfFile;
}

fn printLineInfo(
    out_stream: anytype,
    source_location: ?std.debug.SourceLocation,
    address: usize,
    symbol_name: []const u8,
    compile_unit_name: []const u8,
) !void {
    if (source_location) |*sl| {
        try out_stream.print("{s}:{d}:{d}\n", .{ sl.file_name, sl.line, sl.column });

        inline for (source_files) |src_path| {
            if (std.mem.endsWith(u8, sl.file_name, src_path)) {
                const contents = @embedFile(src_path);
                try printLineFromBuffer(out_stream, contents[0..], source_location.?);
                return;
            }
        }
        try out_stream.print("(source file {s} not embedded)\n", .{source_location.?.file_name});
    } else {
        try out_stream.writeAll("???:?:?");
    }

    try out_stream.writeAll(": ");
    try out_stream.print("0x{x} in {s} ({s})\n", .{ address, symbol_name, compile_unit_name });
}
