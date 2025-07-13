//! Methods relating to TTY
const std = @import("std");
const arch = @import("arch");

/// TTY struct
pub const TTY = struct {
    /// TTY Writer, utilising architecture's own writer method
    pub const writer: std.io.AnyWriter = arch.internals.writer;
};
