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
        const err = sbi.sbi_putstr(data);
        if (err != sbi.SBIErrorCode.SBI_SUCCESS) {
            return error.GENERIC_PRINT_ERROR;
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
/// Silently returns on error
pub fn putchar(char: u8) void {
    _ = sbi.sbi_putchar(char);
}

/// Write a string to the screen.
/// Takes a string as argument.
/// Silently returns on error
pub fn putstr(string: []const u8) void {
    _ = sbi.sbi_putstr(string);
}

/// A formatted print function
/// Takes a format string `fmt` and `args`
/// Silently returns on failure
pub fn format_print(comptime fmt: []const u8, args: anytype) void {
    var display: UARTDisplay = UARTDisplay{};

    return std.fmt.format(display.writer(), fmt, args) catch {};
}
