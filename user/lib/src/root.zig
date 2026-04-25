const stack_top = @extern([*]u8, .{
    .name = "__stack_top",
});

fn exit() noreturn {
    while (true) {}
}

fn start() linksection(".text.start") callconv(.naked) void {
    asm volatile (
        \\mv sp, %[stack_top]
        \\call main
        \\call exit
    );
}
