const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const arch = @import("arch").internals;
const mem = @import("mem");

const kernel_base = @extern([*]u8, .{
    .name = "kernel_base",
});

const free_ram_end = @extern([*]u8, .{
    .name = "free_ram_end",
});

const user_base = 0x1000000;

const satp_sv39 = 8 << 60;
const stack_size = 8192;

const ProcessNode = std.DoublyLinkedList.Node;

var proc_list: std.DoublyLinkedList = .{};

var current_process: *ProcessNode = undefined;

const ProcessState = enum {
    unused,
    runnable,
};

fn processFromNode(node: *ProcessNode) *Process {
    return @fieldParentPtr("node", node);
}

/// Cooperatively yield execution to the next available process.
/// If the calling process is the only available process (barring the idle process), no context switch will occur.
pub fn yield() void {
    const next: *ProcessNode = current_process.next orelse proc_list.first.?.next.?;
    if (next == current_process) {
        return;
    }

    const next_proc = processFromNode(next);

    // Store pointer to bottom of kernel stack
    asm volatile (
        \\sfence.vma
        \\csrw satp, %[satp]
        \\sfence.vma
        \\csrw sscratch, %[sscratch]
        :
        : [satp] "r" (satp_sv39 | (@intFromPtr(processFromNode(next).page_table.ptr) / std.heap.pageSize())),
          [sscratch] "r" (@intFromPtr(&next_proc.stack) + next_proc.stack.len),
    );

    const prev_node: *ProcessNode = current_process;
    current_process = next;

    const prev_proc = processFromNode(prev_node);
    const curr_proc = processFromNode(current_process);
    arch.switch_context(&prev_proc.stack_pointer, &curr_proc.stack_pointer);
}

export fn user_entry() void {
    @panic("Not implemented");
}

pub const Process = struct {
    node: std.DoublyLinkedList.Node = .{},
    id: usize,
    state: ProcessState,
    stack_pointer: *usize,
    page_table: []usize,
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
    pub fn init(allocator: std.mem.Allocator, image: []const u8) !*ProcessNode {
        const process = try allocator.create(Process);

        const page_table = try allocator.alloc(usize, std.heap.pageSize() / @sizeOf(usize));

        // Map kernel pages
        var paddr: usize = @intFromPtr(kernel_base);
        while (paddr < @intFromPtr(free_ram_end)) : (paddr += std.heap.pageSize()) {
            arch.map_page(allocator, page_table, paddr, paddr, 0b1110);
        }

        var off: usize = 0;
        while (off < image.len) : (off += std.heap.pageSize()) {
            const page = try allocator.alloc(u8, std.heap.pageSize());
            const copy_size = @min(std.heap.pageSize(), image.len - off);
            @memcpy(page[0..copy_size], image[off..][0..copy_size]);
            @memset(page[copy_size..], 0);
            arch.map_page(allocator, page_table, @intFromPtr(page.ptr), user_base + off, 0b11110);
        }

        process.* = .{
            .id = proc_list.len(),
            .state = .runnable,
            .stack_pointer = undefined,
            .page_table = page_table,
            .stack = std.mem.zeroes([stack_size]u8),
        };

        // Stack callee-saved registers (s11-s0).
        // The values will be restored in the first context switch
        // Stack as array of words
        const regs: []usize = blk: {
            const ptr: [*]usize = @ptrCast(@alignCast(&process.stack));
            break :blk ptr[0 .. process.stack.len / @sizeOf(usize)];
        };

        // Minus reg_num + 1 for ra from sp
        const sp = regs[regs.len - arch.num_callee_saved_regs ..];

        // sp[0] = ra: trampoline (riscv_process_start) that calls entry then exits
        // sp[1] = s0: actual entry point
        // sp[2] = s1: process_exit function pointer (avoids linker dep in arch module)
        sp[0] = @intFromPtr(arch.process_start);
        sp[1] = @intFromPtr(&user_entry);
        sp[2] = @intFromPtr(&process_exit);

        std.debug.assert(sp.len == arch.num_callee_saved_regs);

        // Zero out remaining callee saved registers
        for (sp[3..]) |*reg| {
            reg.* = 0;
        }

        process.stack_pointer = &sp.ptr[0];

        proc_list.append(&process.node);

        return &process.node;
    }
};

/// Called (via riscv_process_start) when a process entry function returns.
/// Removes the process from the scheduler and switches to the next one.
export fn process_exit() noreturn {
    proc_list.remove(current_process);

    const next: *ProcessNode = if (proc_list.len() == 1)
        proc_list.first.? // only idle remains
    else
        proc_list.first.?.next orelse proc_list.first.?; // prefer first non-idle

    const next_proc = processFromNode(next);
    asm volatile (
        \\csrw sscratch, %[sscratch]
        :
        : [sscratch] "r" (@intFromPtr(&next_proc.stack) + next_proc.stack.len),
    );
    current_process = next;
    var dummy: usize = undefined;
    var dummy_ptr: *usize = &dummy;
    arch.switch_context(&dummy_ptr, &next_proc.stack_pointer);
    unreachable;
}

/// Initialise the process system, creating the idle process (pid 0)
pub fn init(allocator: std.mem.Allocator) !void {
    const process_idle = try Process.init(allocator, &.{});
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
    std.log.info("PID: {}", .{processFromNode(proc_list.first.?).id});
    assert(proc_list.len() == 1);
    assert(processFromNode(current_process).id == 0);

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
}
