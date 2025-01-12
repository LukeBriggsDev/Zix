// Helper methods for dealing with SBI
const common = @import("common.zig");

/// List of SBI error values as defined in the SBI spec:
/// Chapter 3: Binary Encoding.
pub const SBIError = enum(i32) {
    SBI_SUCCESS = 0,
    SBI_ERR_FAILED = -1,
    SBI_ERR_NOT_SUPPORTED = -2,
    SBI_ERR_INVALID_PARAM = -3,
    SBI_ERR_DENIED = -4,
    SBI_ERR_INVALID_ADDRESS = -5,
    SBI_ERR_ALREADY_AVAILABLE = -6,
    SBI_ERR_ALREADY_STARTED = -7,
    SBI_ERR_ALREADY_STOPPED = -8,
    _,
};

/// Return type of SBI ecall
const SBIret = struct {
    err: SBIError,
    val: isize,
};

/// Make an ecall to the SBI ti perform a function.
/// Takes value of registers a0-a5, fid and eid as parameters.
/// Returns an SBIret containing the return value and error code.
fn sbi_call(
    arg0: isize,
    arg1: isize,
    arg2: isize,
    arg3: isize,
    arg4: isize,
    arg5: isize,
    fid: isize,
    eid: isize,
) SBIret {
    var err: isize = 0;
    var val: isize = 0;
    asm volatile ("ecall"
        : [ret] "={a0}" (err),
          [val] "={a1}" (val),
        : [arg0] "{a0}" (arg0),
          [arg1] "{a1}" (arg1),
          [arg2] "{a2}" (arg2),
          [arg3] "{a3}" (arg3),
          [arg4] "{a4}" (arg4),
          [arg5] "{a5}" (arg5),
          [fid] "{a6}" (fid),
          [eid] "{a7}" (eid),
        : "memory"
    );
    return SBIret{
        .err = @enumFromInt(err),
        .val = val,
    };
}

/// Write a character to the screen using SBI extension defined in SBI spec:
/// 5.2. Extension: Console Putchar (EID #0x01).
/// Takes a single u8 character as argument.
/// Returns an SBIError struct containing the error code of the call.
pub fn sbi_putchar(char: u8) SBIError {
    const ret = sbi_call(
        char,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
    );
    return ret.err;
}

/// Write a string to the screen.
/// Takes a slice of characters (u8) and prints them to the screen.
/// Returns an SBIError.
/// If a failure occurs, this is the error code of the first character that failed.
pub fn putstr(string: []const u8) SBIError {
    for (string) |char| {
        const err = sbi_putchar(char);
        if (err != SBIError.SBI_SUCCESS) {
            return err;
        }
    }
    return SBIError.SBI_SUCCESS;
}
