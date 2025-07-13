//! TTY related methods

const sbi = @import("sbi.zig");
const std = @import("std");

/// RV64TTY struct to provide an interface for writing to the terminal via SBI
pub const RV64TTY = struct {
    /// Writer interface for using functions that require it
    const Writer = std.io.GenericWriter(
        *RV64TTY,
        PrintError,
        write,
    );

    /// Part of Writer, appends by directly putting characters to the screen.
    /// Returns number of characters printed or an error.
    fn write(_: *RV64TTY, data: []const u8) PrintError!usize {
        for (data) |char| {
            const err = sbi.sbi_putchar(char);
            if (err != sbi.SBIErrorCode.SBI_SUCCESS) {
                return PrintError.GENERIC_PRINT_ERROR;
            }
        }

        return data.len;
    }

    /// Method to expose UARTDisplay's Writer interface
    pub fn writer(self: *RV64TTY) Writer {
        return .{ .context = self };
    }
};

/// Error enum for print functions
pub const PrintError = error{
    GENERIC_PRINT_ERROR,
};
