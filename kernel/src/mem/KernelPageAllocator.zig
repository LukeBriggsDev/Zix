//! Idea from
//! https://web.archive.org/web/20191128191653/http://osblog.stephenmarz.com/ch3.html
//!
//! At the start of our RAM section we initialize an array of `Page` structs describing all the pages in the heap.
const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const free_ram_start = @extern([*]u8, .{
    .name = "free_ram_start",
});

const free_ram_end = @extern([*]u8, .{
    .name = "free_ram_end",
});

const Allocator = std.mem.Allocator;
const Self = @This();
const KernelPageAllocator = Self;

pub const vtable = Allocator.VTable{
    .alloc = alloc,
    .free = free,
    .resize = resize,
    .remap = remap,
};

/// Inline function to return start of actual allocations
inline fn get_alloc_start() [*]u8 {
    const num_pages = get_heap_size() / std.heap.pageSize();
    return @ptrFromInt(std.mem.Alignment.forward(
        .fromByteUnits(std.heap.pageSize()),
        @intFromPtr(free_ram_start) + (num_pages * @sizeOf(Page)),
    ));
}

/// Inline function to return heap_size
inline fn get_heap_size() usize {
    return @intFromPtr(free_ram_end) - @intFromPtr(free_ram_start);
}

/// Inline function to return number of pages in heap
inline fn get_num_pages() usize {
    return get_heap_size() / std.heap.pageSize();
}

/// Inline function to return how many pages are required to hold `n` bytes
inline fn bytes_to_pages(n: usize) usize {
    return (n + std.heap.pageSize() - 1) / std.heap.pageSize();
}

/// Struct containing Page descriptor values
const Page = packed struct {
    /// Is page taken?
    taken: bool,
    /// Is it the last page in the allocation?
    last: bool,
};

/// Convert a address at the beginning of a page to a page descriptor describing it
inline fn address_to_descriptor(address: [*]u8) [*]Page {
    // Assert address is on a page boundary
    assert(std.mem.Alignment.check(.fromByteUnits(std.heap.pageSize()), @intFromPtr(address)));
    return @ptrFromInt(@intFromPtr(free_ram_start) + (@intFromPtr(address) - @intFromPtr(get_alloc_start())) / std.heap.pageSize());
}

/// Convert a descriptor address to the beginning of the page it describes
inline fn descriptor_to_address(descriptor: [*]Page) [*]u8 {
    return @ptrFromInt(((@intFromPtr(descriptor) - @intFromPtr(free_ram_start)) * std.heap.pageSize()) + @intFromPtr(get_alloc_start()));
}

/// Return a new instance of the allocator
pub fn new() Self {
    return Self{};
}

/// Initialize the heap metadata block
pub fn init() void {
    std.log.debug("heap_size initialized: {d}", .{get_heap_size()});
    const ptr: [*]Page = @ptrCast(free_ram_start);
    for (0..get_num_pages()) |i| {
        ptr[i] = Page{ .taken = false, .last = false };
    }

    std.log.debug("alloc_start initialized: {*}", .{get_alloc_start()});
}

/// Allocate `pages` number of pages.
/// Returns either a pointer to the allocated pages or an allocator Error.
fn alloc_pages(n: usize) ?[*]u8 {
    std.log.info("Allocating {} pages", .{n});
    var ptr: [*]Page = @ptrCast(free_ram_start);

    // Check beginning of heap to last possible page we can start allocating from
    for (0..get_num_pages() - n) |i| {
        var found = false;

        // Check to see if the page is free, if so we have a possible candidate
        if (!ptr[i].taken) {
            // It was free
            found = true;
            for (i..i + n) |j| {
                // Check if we have a contiguous allocation, if not check elsewhere.
                if (ptr[j].taken) {
                    found = false;
                    break;
                }
            }
        }

        // Mark as taken
        if (found) {
            std.log.info("Found free page {}", .{i});
            for (i..i + n - 1) |j| {
                std.log.info("Claiming page {} {*}", .{ j, &ptr[j] });
                ptr[j].taken = true;
            }
            std.log.info("Claiming page {}, {*}", .{ i + n - 1, &ptr[i + n - 1] });
            ptr[i + n - 1] = Page{ .taken = true, .last = true };
            ptr = @ptrCast(free_ram_start + std.heap.pageSize() * i);
            std.log.debug("alloc_start: {*}", .{get_alloc_start()});

            const ret: [*]u8 = @ptrFromInt(@intFromPtr(get_alloc_start()) + std.heap.pageSize() * i);
            std.log.info("Returned ptr: {*}", .{ret});
            return ret;
        }
    }

    // Return null if exhausted search
    return null;
}

/// Allocate enough pages to hold too few operands for instruction`n` bytes
///
/// No alignment parameter is necessary as zig specifies alignment cannot be more then the page size (<https://github.com/ziglang/zig/blob/a03ab9ee01129913af526a38b688313ccd83dca2/lib/std/mem/Allocator.zig#L218>)
/// A return address is also not required.
/// Returns either a pointer to the allocated pages or an allocator Error.
fn alloc(_: *anyopaque, n: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    // Allocate pages
    std.log.info("Alignment: {}", .{alignment});
    return alloc_pages(bytes_to_pages(n));
}

/// Free a page pointed to by `memory`.
/// Alignment is not necessary due to Zig's maximum allocaion alignment being the page size.
/// A return address is not used.
fn free(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
    const descriptor_addr = address_to_descriptor(memory.ptr);
    // Make sure the address is within our heap
    assert(@intFromPtr(descriptor_addr) >= @intFromPtr(free_ram_start) and @intFromPtr(descriptor_addr) < @intFromPtr(free_ram_start) + get_num_pages());
    var pages: [*]Page = @ptrCast(descriptor_addr);

    // Set all but the last page to be free
    while (pages[0].taken and !pages[0].last) {
        pages[0].taken = false;
        pages[0].last = false;
        pages = pages + 1;
    }

    // If the following occurs it is likely due to a double free
    assert(pages[0].last);

    // Here we have taken care of all previous pages and on the last page
    pages[0].taken = false;
    pages[0].last = false;
}

/// Resize allocation `memory` to fit `new_len` bytes.
/// Alignment not necessary since Zig allocators do not align greater than the page size.
fn resize(allocator: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    const descriptor_addr = address_to_descriptor(memory.ptr);
    // Make sure the address is within our heap
    assert(@intFromPtr(descriptor_addr) >= @intFromPtr(free_ram_start) and @intFromPtr(descriptor_addr) < @intFromPtr(free_ram_start) + get_heap_size());
    var pages: [*]Page = @ptrCast(descriptor_addr);

    const old_last_page = bytes_to_pages(memory.len);
    const new_last_page = bytes_to_pages(new_len);

    if (old_last_page == new_last_page) {
        return true;
    }

    if (new_last_page < old_last_page) {
        const new_last_page_addr = descriptor_to_address(@ptrCast(&pages[new_last_page]));
        const old_last_page_addr = descriptor_to_address(@ptrCast(&pages[old_last_page]));

        // Shrink allocation
        free(allocator, new_last_page_addr[0 .. old_last_page_addr - new_last_page_addr], alignment, ret_addr);
        // Set last page flag
        pages[new_last_page - 1].last = true;
        return true;
    }

    // Check if any pages from end of old memory to new size is taken
    for (old_last_page..new_last_page) |i| {
        if (pages[i].taken) {
            return false;
        }
    }

    // Assert the last memory page is indeed the last page
    assert(pages[old_last_page - 1].last);
    // Resize
    pages[old_last_page - 1].last = false;
    for (old_last_page..new_last_page) |i| {
        pages[i].taken = true;
    }
    pages[new_last_page - 1].last = true;

    return true;
}

/// Remap memory, providing null if it would be no more efficient than freeing and copying.
/// Since this is in physical address space, the best we can do is attempt to resize.
fn remap(allocator: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    if (!resize(allocator, memory, alignment, new_len, ret_addr)) {
        return null;
    }
    // No relocation possible in physical memory without copying
    return memory.ptr;
}

// Tests

test "Expect init to zero" {
    // Ensure Init initialises all memory to zero
    init();
    const ptr: [*]Page = @ptrCast(free_ram_start);
    for (0..get_num_pages()) |i| {
        try std.testing.expect(!ptr[i].taken);
        try std.testing.expect(!ptr[i].last);
    }
}

test "Expect successful allocation" {
    var test_allocator_instance = new();
    const test_allocator = Allocator{ .vtable = &vtable, .ptr = &test_allocator_instance };
    // Initialise and allocate page
    init();
    const page = try test_allocator.alloc(u8, 1 * std.heap.pageSize());

    // Check a single page has been allocated
    const ptr: [*]Page = @ptrCast(free_ram_start);
    try std.testing.expect(ptr[0].taken);
    try std.testing.expect(ptr[0].last);

    // Check no other pages have been allocated
    for (1..get_num_pages()) |i| {
        try std.testing.expect(!ptr[i].taken);
        try std.testing.expect(!ptr[i].last);
    }

    // Free page
    test_allocator.free(page);
    // Check all pages unallocated
    for (0..get_num_pages()) |i| {
        try std.testing.expect(!ptr[i].taken);
        try std.testing.expect(!ptr[i].last);
    }

    // Allocate 2 pages
    const double_page = try test_allocator.alloc(u8, 2 * std.heap.pageSize());
    // allocate 3 pages
    const triple_page = try test_allocator.alloc(u8, 3 * std.heap.pageSize());
    // allocate 1 page
    const buffer_page = try test_allocator.alloc(u8, 1 * std.heap.pageSize());
    // free triple page
    test_allocator.free(triple_page);

    // Allocate 4 pages
    const quad_page = try test_allocator.alloc(u8, 4 * std.heap.pageSize());

    // Quad page should have been placed after buffer page
    try std.testing.expect(ptr[0].taken);
    try std.testing.expect(!ptr[0].last);
    try std.testing.expect(ptr[1].taken);
    try std.testing.expect(ptr[1].last);

    // Unallocated gap
    for (2..5) |i| {
        try std.testing.expect(!ptr[i].taken);
    }

    // Buffer page
    try std.testing.expect(ptr[5].taken);
    try std.testing.expect(ptr[5].last);

    // Quad page
    for (6..10) |i| {
        try std.testing.expect(ptr[i].taken);
    }

    // Free pages
    test_allocator.free(double_page);
    test_allocator.free(buffer_page);
    test_allocator.free(quad_page);
}

test "Resize smaller" {
    var test_allocator_instance = new();
    const test_allocator = Allocator{ .vtable = &vtable, .ptr = &test_allocator_instance };
    // Initialise and allocate page
    init();
    const big_alloc = try test_allocator.alloc(u8, 5 * std.heap.pageSize());

    // Resize smaller
    try std.testing.expect(test_allocator.resize(big_alloc, 3 * std.heap.pageSize()));

    // Check 3 pages are allocated
    const ptr: [*]Page = @ptrCast(free_ram_start);

    for (0..2) |i| {
        try std.testing.expect(ptr[i].taken);
        try std.testing.expect(!ptr[i].last);
    }
    try std.testing.expect(ptr[2].taken);
    try std.testing.expect(ptr[2].last);

    // Check the other two pages are now deallocated
    for (3..5) |i| {
        try std.testing.expect(!ptr[i].taken);
        try std.testing.expect(!ptr[i].last);
    }
}

test "Resize larger" {
    var test_allocator_instance = new();
    const test_allocator = Allocator{ .vtable = &vtable, .ptr = &test_allocator_instance };
    // Initialise and allocate page
    init();
    const big_alloc = try test_allocator.alloc(u8, 5 * std.heap.pageSize());

    // Check 5 pages are allocated
    const ptr: [*]Page = @ptrCast(free_ram_start);

    for (0..4) |i| {
        try std.testing.expect(ptr[i].taken);
        try std.testing.expect(!ptr[i].last);
    }
    try std.testing.expect(ptr[4].taken);
    try std.testing.expect(ptr[4].last);

    // Resize larger
    try std.testing.expect(test_allocator.resize(big_alloc, 8 * std.heap.pageSize()));

    // Check the pages
    for (0..7) |i| {
        try std.testing.expect(ptr[i].taken);
        try std.testing.expect(!ptr[i].last);
    }
    try std.testing.expect(ptr[7].taken);
    try std.testing.expect(ptr[7].last);
}

test {
    std.testing.refAllDecls(@This());
}
