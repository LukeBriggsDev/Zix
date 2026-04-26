comptime {
    // Comptime import so that this isn't lazy loaded
    _ = @import("zixlib");
}

export fn main() void {
    while (true) {}
}
