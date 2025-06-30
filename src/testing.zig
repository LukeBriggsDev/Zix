const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");

var display = common.UARTDisplay{};

pub const std_options: std.Options = .{
    .page_size_min = 4096,
    .page_size_max = 4 * 1024,
};

pub fn main() noreturn {
    for (builtin.test_functions) |t| {
        t.func() catch |err| {
            std.fmt.format(display.writer(), "{s} fail: {}\n", .{ t.name, err }) catch {};
            continue;
        };
        std.fmt.format(display.writer(), "{s} passed\n", .{t.name}) catch {};
    }
    while (true) {}
}
