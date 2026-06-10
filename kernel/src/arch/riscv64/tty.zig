//! TTY related methods

const sbi = @import("sbi.zig");
const std = @import("std");

fn drain(_: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    var written: usize = 0;
    for (data, 0..) |slice, i| {
        const times: usize = if (i == data.len - 1) splat else 1;
        var t: usize = 0;
        while (t < times) : (t += 1) {
            for (slice) |byte| {
                if (sbi.sbi_putchar(byte) != .SBI_SUCCESS) return error.WriteFailed;
            }
            written += slice.len;
        }
    }
    return written;
}

const vtable: std.Io.Writer.VTable = .{ .drain = drain };

pub var writer_instance: std.Io.Writer = .{
    .vtable = &vtable,
    .buffer = &.{},
};

/// Error enum for print functions
pub const PrintError = error{
    GENERIC_PRINT_ERROR,
};
