// Code derived from https://github.com/benburkert/freestanding.zig/

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx.zig");

const source_files: []const []const u8 = &.{
    "arch/arch.zig",
    "arch/riscv64/arch.zig",
    "arch/riscv64/csr.zig",
    "arch/riscv64/sbi.zig",
    "arch/riscv64/tty.zig",
    "debug.zig",
    "io/io.zig",
    "io/tty.zig",
    "kernel.zig",
    "mem/KernelPageAllocator.zig",
    "mem/mem.zig",
};

pub const DebugInfo = @This();

pub const Symbols = struct {
    debug_info: [2]@Type(.enum_literal) = [_]@Type(.enum_literal){ .@".debug_info_start", .@".debug_info_end" },
    debug_abbrev: [2]@Type(.enum_literal) = [_]@Type(.enum_literal){ .@".debug_abbrev_start", .@".debug_abbrev_end" },
    debug_str: [2]@Type(.enum_literal) = [_]@Type(.enum_literal){ .@".debug_str_start", .@".debug_str_end" },
    debug_line: [2]@Type(.enum_literal) = [_]@Type(.enum_literal){ .@".debug_line_start", .@".debug_line_end" },
    debug_ranges: [2]@Type(.enum_literal) = [_]@Type(.enum_literal){ .@".debug_ranges_start", .@".debug_ranges_end" },

    fn section(self: @This(), comptime symbol: std.meta.FieldEnum(@This())) []const u8 {
        const start_addr = addressOf(@field(self, @tagName(symbol))[0]);
        const end_addr = addressOf(@field(self, @tagName(symbol))[1]);

        const sgmt: [*]u8 = @ptrFromInt(start_addr);
        return sgmt[0..((end_addr - start_addr) / @sizeOf(u8))];
    }

    fn addressOf(symbol: @Type(.enum_literal)) usize {
        return @intFromPtr(@extern(*anyopaque, .{ .name = @tagName(symbol) }));
    }
};

allocator: std.mem.Allocator,
elf_module: stdx.debug.Dwarf.ElfModule,

pub fn init(allocator: std.mem.Allocator, symbols: Symbols) !DebugInfo {
    const debug_info = symbols.section(.debug_info);
    const debug_abbrev = symbols.section(.debug_abbrev);
    const debug_str = symbols.section(.debug_str);
    const debug_line = symbols.section(.debug_line);
    const debug_ranges = symbols.section(.debug_ranges);

    var sections = stdx.debug.Dwarf.null_section_array;
    sections[@intFromEnum(stdx.debug.Dwarf.Section.Id.debug_info)] = .{
        .data = debug_info,
        .virtual_address = @intFromPtr(debug_info.ptr),
        .owned = false,
    };
    sections[@intFromEnum(stdx.debug.Dwarf.Section.Id.debug_abbrev)] = .{
        .data = debug_abbrev,
        .virtual_address = @intFromPtr(debug_abbrev.ptr),
        .owned = false,
    };
    sections[@intFromEnum(stdx.debug.Dwarf.Section.Id.debug_str)] = .{
        .data = debug_str,
        .virtual_address = @intFromPtr(debug_str.ptr),
        .owned = false,
    };
    sections[@intFromEnum(stdx.debug.Dwarf.Section.Id.debug_line)] = .{
        .data = debug_line,
        .virtual_address = @intFromPtr(debug_line.ptr),
        .owned = false,
    };
    sections[@intFromEnum(stdx.debug.Dwarf.Section.Id.debug_ranges)] = .{
        .data = debug_ranges,
        .virtual_address = @intFromPtr(debug_ranges.ptr),
        .owned = false,
    };

    var dwarf: stdx.debug.Dwarf = .{
        .endian = builtin.target.cpu.arch.endian(),
        .sections = sections,
        .is_macho = false,
    };
    try dwarf.open(allocator);
    return .{
        .allocator = allocator,
        .elf_module = .{
            .base_address = 0,
            .dwarf = dwarf,
            .mapped_memory = undefined,
            .external_mapped_memory = undefined,
        },
    };
}

pub fn deinit(self: *DebugInfo) void {
    self.elf_module.dwarf.deinit(self.allocator);

    self.* = undefined;
}

pub fn printStackTrace(self: *DebugInfo, writer: anytype, return_address: usize, frame_address: usize) !void {
    var it = std.debug.StackIterator.init(return_address, frame_address);
    defer it.deinit();

    while (it.next()) |address| {
        const symbol = try self.elf_module.getSymbolAtAddress(self.allocator, address);
        defer if (symbol.source_location) |sl| self.allocator.free(sl.file_name);

        try printLineInfo(
            writer,
            symbol.source_location,
            address,
            symbol.name,
            symbol.compile_unit_name,
            .escape_codes,
        );
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
    tty_config: std.io.tty.Config,
) !void {
    try tty_config.setColor(out_stream, .bold);

    if (source_location) |*sl| {
        try out_stream.print("{s}:{d}:{d}\n", .{ sl.file_name, sl.line, sl.column });

        inline for (source_files) |src_path| {
            if (std.mem.endsWith(u8, sl.file_name, src_path)) {
                const contents = @embedFile(src_path);
                try printLineFromBuffer(out_stream, contents[0..], source_location.?);
                return;
            }
        }
        try out_stream.print("(source file {s} not added in std/debug.zig)\n", .{source_location.?.file_name});
    } else {
        try out_stream.writeAll("???:?:?");
    }

    try tty_config.setColor(out_stream, .reset);
    try out_stream.writeAll(": ");
    try tty_config.setColor(out_stream, .dim);
    try out_stream.print("0x{x} in {s} ({s})", .{ address, symbol_name, compile_unit_name });
    try tty_config.setColor(out_stream, .reset);
    try out_stream.writeAll("\n");
}
