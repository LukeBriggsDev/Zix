const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const log = std.log;
var display = common.UARTDisplay{};

pub const std_options: std.Options = .{
    .page_size_min = 4096,
    .page_size_max = 4 * 1024,
    .log_level = .info,
    .logFn = logFn,
};

pub fn logFn(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime format: []const u8, args: anytype) void {
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ @tagName(scope) ++ " ";

    // Print message
    common.format_print(prefix ++ format ++ "\n", args);
}

fn test_loader() void {
    _ = @import("alloc.zig");
}

pub fn main() noreturn {
    log.info("Starting tests...", .{});
    test_loader();
    const test_functions = builtin.test_functions;
    log.info("Found {} tests", .{test_functions.len});
    for (test_functions) |t| {
        t.func() catch |err| {
            log.err("{s} fail: {}", .{ t.name, err });
            continue;
        };
        log.info("{s} passed", .{t.name});
    }
    log.info("Finished tests.", .{});
    while (true) {}
}

test {
    std.testing.refAllDecls(@This());
}
