const Allocator = @import("std").mem.Allocator;
const KernelPageAllocator = @import("mem/KernelPageAllocator.zig");
var kernel_page_allocator_instance = KernelPageAllocator.new();

/// Allocator which allocates physical pages. For use in kernel space.
pub const kernel_page_allocator = Allocator{
    .ptr = &kernel_page_allocator_instance,
    .vtable = &KernelPageAllocator.vtable,
};

/// Initialize Kernel Page Allocator, zeroing out descriptor array
pub fn initKernelPageAllocator() void {
    KernelPageAllocator.init();
}
