const std = @import("std");

const stack_top = @extern([*]u8, .{
    .name = "__stack_top",
});

pub const syscall_no = enum(isize) {
    putchar = 1,
    getchar = 2,
};

export fn exit() noreturn {
    while (true) {}
}

export fn start() linksection(".text.start") callconv(.naked) void {
    asm volatile (
        \\mv sp, %[stack_top]
        \\call main
        \\call exit
        :
        : [stack_top] "r" (stack_top),
    );
}

pub fn syscall(
    sysno: usize,
    arg0: usize,
    arg1: usize,
    arg2: usize,
) usize {
    return asm volatile ("ecall"
        : [ret] "={a0}" (-> usize),
        : [arg0] "{a0}" (arg0),
          [arg1] "{a1}" (arg1),
          [arg2] "{a2}" (arg2),
          [sysno] "{a3}" (sysno),
        : .{ .memory = true });
}

pub const SerialWriter = struct {
    pub const Writer = struct {
        context: *SerialWriter,

        pub fn write(_: Writer, data: []const u8) PrintError!usize {
            for (data) |char| {
                putchar(char);
            }
            return data.len;
        }

        pub fn writeAll(self: Writer, data: []const u8) PrintError!void {
            _ = try self.write(data);
        }
    };

    pub fn writer(serial_writer: *SerialWriter) Writer {
        return .{ .context = serial_writer };
    }
};

pub fn putchar(c: u8) void {
    _ = syscall(@intFromEnum(syscall_no.putchar), @intCast(c), 0, 0);
}

pub fn getchar() u8 {
    const ret = syscall(@intFromEnum(syscall_no.getchar), 0, 0, 0);
    if (ret > std.math.maxInt(u8)) {
        @panic("Received bad character from getchar");
    }

    return @intCast(ret);
}

/// Error enum for print functions
pub const PrintError = error{
    GENERIC_PRINT_ERROR,
};
