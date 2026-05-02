const zixlib = @import("zixlib");

export fn main() void {
    var w = zixlib.SerialWriter{};
    _ = w.writer().write("Hello\n") catch {
        unreachable;
    };
}
