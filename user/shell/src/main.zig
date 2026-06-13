const zixlib = @import("zixlib");

export fn main() void {
    var w = zixlib.SerialWriter{};

    const writer = w.writer();
    _ = writer.write("Hello\n") catch {
        unreachable;
    };

    const c = zixlib.getchar();

    _ = writer.write(&[_]u8{c}) catch {
        unreachable;
    };
}
