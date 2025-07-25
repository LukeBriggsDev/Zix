const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const arch = @import("arch").internals;
const mem = @import("mem");

const stack_size = 8192;

var proc_list = std.DoublyLinkedList(Process){};

const ProcessState = enum {
    unused,
    runnable,
};

const Process = struct {
    id: usize,
    state: ProcessState,
    stack_pointer: *usize,
    stack: [stack_size]u8 align(@sizeOf(usize)),

    pub fn init(allocator: std.mem.Allocator, program_counter: *const anyopaque) !*Process {
        std.log.info("Starting process", .{});

        const L = std.DoublyLinkedList(Process);
        var node = try allocator.create(L.Node);
        node.data = .{
            .id = proc_list.len + 1,
            .state = .runnable,
            .stack_pointer = undefined,
            .stack = std.mem.zeroes([stack_size]u8),
        };

        // Stack callee-saved registers (s11-s0).
        // The values will be restored in the first context switch
        // Stack as arrat of words
        const regs: []usize = blk: {
            const ptr: [*]usize = @alignCast(@ptrCast(&node.data.stack));
            break :blk ptr[0 .. node.data.stack.len / @sizeOf(usize)];
        };

        // Minus reg_num + 1 for ra from sp
        const sp = regs[regs.len - arch.num_callee_saved_regs - 1 ..];

        // Add program counter to stack
        sp[0] = @intFromPtr(program_counter);

        std.debug.assert(sp.len == arch.num_callee_saved_regs + 1);

        // Zero out callee saved registers
        for (sp[1..]) |*reg| {
            reg.* = 0;
        }

        node.data.stack_pointer = &sp.ptr[0];

        return &node.data;
    }
};

test "Process pid start at 1" {
    const test_funcs = struct {
        var process_a: *Process = undefined;
        var process_b: *Process = undefined;
        fn delay() void {
            for (0..30000000) |_| {
                asm volatile ("nop");
            }
        }

        fn proc_a_entry() void {
            std.log.info("Starting process A", .{});
            std.log.info("proc a fp: {*}, proc b fp: {*}", .{
                &proc_a_entry,
                &proc_b_entry,
            });
            std.log.info("Proc a sp: {*}, proc b sp: {*}", .{
                process_a.stack_pointer,
                process_b.stack_pointer,
            });
            while (true) {
                std.fmt.format(arch.writer, "A", .{}) catch {};
                arch.switch_context(@intFromPtr(&process_a.stack_pointer), @intFromPtr(&process_b.stack_pointer));
                delay();
            }
        }

        fn proc_b_entry() void {
            std.log.info("Starting process B", .{});
            while (true) {
                std.fmt.format(arch.writer, "B", .{}) catch {};
                arch.switch_context(@intFromPtr(&process_b.stack_pointer), @intFromPtr(&process_a.stack_pointer));
                delay();
            }
        }
    };

    mem.initKernelPageAllocator();
    std.log.info("Creating allocator", .{});
    const process_a = try Process.init(mem.kernel_page_allocator, &test_funcs.proc_a_entry);
    std.log.info("Initialized process a", .{});
    const process_b = try Process.init(mem.kernel_page_allocator, &test_funcs.proc_b_entry);
    std.log.info("Initialized process b", .{});
    test_funcs.process_a = process_a;
    std.log.info("Assigned process a", .{});
    test_funcs.process_b = process_b;
    std.log.info("Assigned process b", .{});
    test_funcs.proc_a_entry();
}
