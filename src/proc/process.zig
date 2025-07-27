const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const arch = @import("arch").internals;
const mem = @import("mem");

const stack_size = 8192;

const ProcessNode = std.DoublyLinkedList(Process).Node;

var proc_list = std.DoublyLinkedList(Process){};

var current_process: *ProcessNode = undefined;

const ProcessState = enum {
    unused,
    runnable,
};

/// Cooperatively yield execution to the next available process.
/// If the calling process is the only available process (barring the idle process), no context switch will occur.
fn yield() void {
    if (proc_list.len <= 2) {
        // Don't yield to idle
        return;
    }

    const next: *ProcessNode = current_process.next orelse proc_list.first.?.next.?;
    if (next == current_process) {
        return;
    }

    // Store pointer to bottom of kernel stack
    asm volatile (
        \\csrw sscratch, %[sscratch]
        :
        : [sscratch] "r" (@intFromPtr(&next.data.stack) + next.data.stack.len),
    );

    var prev_proc: *ProcessNode = current_process;
    current_process = next;

    arch.switch_context(&prev_proc.data.stack_pointer, &current_process.data.stack_pointer);
}

const Process = struct {
    id: usize,
    state: ProcessState,
    stack_pointer: *usize,
    stack: [stack_size]u8 align(@sizeOf(usize)),

    pub fn print_stack_regs(self: *Process) void {
        for (0..arch.num_callee_saved_regs) |reg| {
            std.fmt.format(arch.writer, "0x", .{}) catch {};
            for (0..@sizeOf(usize)) |byte| {
                std.fmt.format(arch.writer, "{x}", .{self.stack[self.stack.len - 1 - (reg * @sizeOf(usize) + byte)]}) catch {};
            }
            std.fmt.format(arch.writer, "\n", .{}) catch {};
        }
    }

    /// Initialize a `Process`, providing it's fields and adding it to the process list.
    pub fn init(allocator: std.mem.Allocator, program_counter: *const anyopaque) !*ProcessNode {
        const L = std.DoublyLinkedList(Process);
        var node = try allocator.create(L.Node);
        node.data = .{
            .id = proc_list.len,
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
        const sp = regs[regs.len - arch.num_callee_saved_regs ..];

        // Add program counter to stack
        sp[0] = @intFromPtr(program_counter);

        std.debug.assert(sp.len == arch.num_callee_saved_regs);

        // Zero out callee saved registers
        for (sp[1..]) |*reg| {
            reg.* = 0;
        }

        node.data.stack_pointer = &sp.ptr[0];

        proc_list.append(node);

        return node;
    }
};

/// Initialise the process system, creating the idle process (pid 0)
pub fn init(allocator: std.mem.Allocator) !void {
    std.log.info("Creating allocator", .{});
    const process_idle = try Process.init(allocator, undefined);
    current_process = process_idle;
}

test "Context switch 20 times" {
    const test_funcs = struct {
        var a_counter: usize = 0;
        var b_counter: usize = 0;
        fn proc_a_entry() void {
            std.log.info("Starting process A", .{});

            for (0..20) |_| {
                a_counter += 1;
                std.fmt.format(arch.writer, "A", .{}) catch {};
                yield();
            }
        }

        fn proc_b_entry() void {
            std.log.info("Starting process B", .{});
            for (0..20) |_| {
                b_counter += 1;
                std.fmt.format(arch.writer, "B", .{}) catch {};
                yield();
            }
        }
    };

    mem.initKernelPageAllocator();
    init(mem.kernel_page_allocator) catch {
        @panic("Failed to initialize");
    };

    std.log.info("Initialized process idle", .{});
    std.log.info("PID: {}", .{proc_list.first.?.data.id});
    assert(proc_list.len == 1);
    assert(current_process.data.id == 0);

    const process_a = try Process.init(mem.kernel_page_allocator, &test_funcs.proc_a_entry);
    _ = process_a;
    std.log.info("Initialized process a", .{});
    const process_b = try Process.init(mem.kernel_page_allocator, &test_funcs.proc_b_entry);
    _ = process_b;
    std.log.info("Initialized process b", .{});
    current_process = proc_list.first.?;
    yield();
    assert(test_funcs.a_counter == 20);
    assert(test_funcs.b_counter == 20);
    @panic("switch to idle process");
}
