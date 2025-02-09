// A list of common functions shared across kernel and user space
const sbi = @import("sbi.zig");
const std = @import("std");

/// UARTDisplay struct to provide an interface for writing to the terminal
pub const UARTDisplay = struct {
    /// Writer interface for using functions that require it
    const Writer = std.io.Writer(
        *UARTDisplay,
        PrintError,
        appendWrite,
    );

    /// Part of Writer, appends by directly putting characters to the screen
    fn appendWrite(_: *UARTDisplay, data: []const u8) PrintError!usize {
        for (data) |char| {
            putchar(char) catch {
                return error.GENERIC_PRINT_ERROR;
            };
        }
        return data.len;
    }

    /// Method to expose UARTDisplay's Writer interface
    pub fn writer(self: *UARTDisplay) Writer {
        return .{ .context = self };
    }
};

/// Error enum for print functions
pub const PrintError = error{
    GENERIC_PRINT_ERROR,
};

/// Write a character to the screen.
/// Takes a single u8 character as argument.
/// Returns an PrintError struct containing the error code of the call.
pub fn putchar(char: u8) PrintError!void {
    const err = sbi.sbi_putchar(char);
    if (err != sbi.SBIErrorCode.SBI_SUCCESS) {
        return PrintError.GENERIC_PRINT_ERROR;
    }
}

/// A formatted print function
pub fn format_print(comptime fmt: []const u8, args: anytype) PrintError!void {
    var display: UARTDisplay = UARTDisplay{};

    return std.fmt.format(display.writer(), fmt, args);
}

/// A non-formatted print
pub fn print(str: []const u8) PrintError!usize {
    var display: UARTDisplay = UARTDisplay{};
    return display.appendWrite(str);
}
