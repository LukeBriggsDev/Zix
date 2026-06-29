const zixlib = @import("zixlib");
const std = @import("std");

export fn main() void {
    var w = zixlib.SerialWriter{};

    const writer = w.writer();
    _ = writer.write("Hello\n") catch {
        unreachable;
    };

    _ = writer.write("\nDone\n") catch {
        unreachable;
    };
}
