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

    fn addressOf(symbol: @EnumLiteral()) usize {
        return @intFromPtr(@extern(*anyopaque, .{ .name = @tagName(symbol) }));
    }
};

allocator: std.mem.Allocator,
dwarf: std.debug.Dwarf,

const endian = builtin.target.cpu.arch.endian();

pub fn init(allocator: std.mem.Allocator, symbols: Symbols) !DebugInfo {
    const Sid = std.debug.Dwarf.Section.Id;
    var sections: std.debug.Dwarf.SectionArray = @splat(null);
    sections[@intFromEnum(Sid.debug_info)]   = .{ .data = symbols.section(.debug_info),   .owned = false };
    sections[@intFromEnum(Sid.debug_abbrev)] = .{ .data = symbols.section(.debug_abbrev), .owned = false };
    sections[@intFromEnum(Sid.debug_str)]    = .{ .data = symbols.section(.debug_str),    .owned = false };
    sections[@intFromEnum(Sid.debug_line)]   = .{ .data = symbols.section(.debug_line),   .owned = false };
    sections[@intFromEnum(Sid.debug_ranges)] = .{ .data = symbols.section(.debug_ranges), .owned = false };
    var dwarf: std.debug.Dwarf = .{ .sections = sections };
    try dwarf.open(allocator, endian);
    return .{ .allocator = allocator, .dwarf = dwarf };
}

pub fn deinit(self: *DebugInfo) void {
    self.dwarf.deinit(self.allocator);
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
        // Subtract 1 so the address lands on the call instruction, not the
        // instruction after it — DWARF lookup then gives the correct source line.
        const lookup_addr = address - 1;
        const sym_name = self.dwarf.getSymbolName(lookup_addr) orelse "???";

        const cu = self.dwarf.findCompileUnit(endian, lookup_addr) catch {
            try printLineInfo(writer, null, address, sym_name, "???");
            continue;
        };

        if (cu.src_loc_cache == null) {
            self.dwarf.populateSrcLocCache(self.allocator, endian, cu) catch {
                try printLineInfo(writer, null, lookup_addr, sym_name, "???");
                continue;
            };
        }

        const cu_name = cu.die.getAttrString(&self.dwarf, endian, DW.AT.name, self.dwarf.section(.debug_str), cu) catch "???";

        const src_loc: ?std.debug.SourceLocation = blk: {
            const cache = &cu.src_loc_cache.?;
            const le = cache.findSource(lookup_addr) catch break :blk null;
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

        try printLineInfo(writer, src_loc, lookup_addr, sym_name, cu_name);
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
