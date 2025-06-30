//! Idea from
//! https://web.archive.org/web/20191128191653/http://osblog.stephenmarz.com/ch3.html
//!
//! At the start of our RAM section we initialize an array of `Page` structs describing all the pages in the heap.
const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const common = @import("common.zig");

const free_ram_start = @extern([*]u8, .{
    .name = "free_ram_start",
});

const free_ram_end = @extern([*]u8, .{
    .name = "free_ram_end",
});

/// Inline function to return start of actual allocations
pub inline fn get_alloc_start() [*]u8 {
    const num_pages = get_heap_size() / std.heap.pageSize();
    return @ptrFromInt(align_val(@intFromPtr(free_ram_start) + num_pages + @bitSizeOf(Page), 12));
}

/// Inline function to return heap_size
inline fn get_heap_size() usize {
    return @intFromPtr(free_ram_end) - @intFromPtr(free_ram_start);
}

/// Struct containing Page descriptor values
const Page = packed struct {
    /// Is page taken?
    taken: bool,
    /// Is it the last page in the allocation?
    last: bool,
};

/// Align a value `val` to a given power `order` of 2
fn align_val(val: usize, order: u6) usize {
    std.log.debug("Aligning {x} to page size {d}", .{ val, std.math.pow(usize, 2, order) });
    const o: usize = (@as(usize, 1) << order) - 1;
    std.log.debug("= {x}", .{(val + o) & ~o});
    return (val + o) & ~o;
}

/// Initialize the heap metadata block
pub fn init() void {
    std.log.debug("heap_size initialized: {d}", .{get_heap_size()});
    const num_pages = get_heap_size() / std.heap.pageSize();
    const ptr: [*]Page = @ptrCast(free_ram_start);
    for (0..num_pages) |i| {
        ptr[i] = Page{ .taken = false, .last = false };
    }

    std.log.debug("alloc_start initialized: {*}", .{get_alloc_start()});
}

/// Allocate `pages` number of pages.
/// Returns either a pointer to the allocated pages or an allocator Error.
pub fn alloc_page(pages: usize) std.mem.Allocator.Error![*]u8 {
    assert(pages > 0);

    // Create a page structure for each page on the heap
    const num_pages = get_heap_size() / std.heap.pageSize();

    std.log.debug("heap_size: {d}, num_pages: {d}", .{ get_heap_size(), num_pages });

    var ptr: [*]Page = @ptrCast(free_ram_start);

    // Check beginning of heap to last possible page we can start allocating from
    for (0..num_pages - pages) |i| {
        var found = false;

        // Check to see if the page is free, if so we have a possible candidate
        if (!ptr[i].taken) {
            // It was free
            found = true;
            for (i..i + pages) |j| {
                // Check if we have a contiguous allocation, if not check elsewhere.
                if (ptr[j].taken) {
                    found = false;
                    break;
                }
            }
        }

        // Mark as taken
        if (found) {
            for (i..i + pages - 1) |j| {
                ptr[j].taken = true;
            }
            ptr[i + pages - 1] = Page{ .taken = true, .last = true };
            ptr = @ptrCast(free_ram_start + std.heap.pageSize() * i);
            std.log.debug("alloc_start: {*}", .{get_alloc_start()});
            return @ptrFromInt(@intFromPtr(get_alloc_start()) + std.heap.pageSize() * i);
        }
    }

    std.log.err("Out of memory!", .{});
    // Return null if exhausted search
    return std.mem.Allocator.Error.OutOfMemory;
}

/// De-allocate a page pointed to by `ptr`
pub fn free_page(ptr: [*]u8) void {
    std.log.debug(
        "heap start: {*}, ptr: {*}, alloc start: {*}",
        .{
            free_ram_start,
            ptr,
            get_alloc_start(),
        },
    );
    const descriptor_addr: [*]u8 = @ptrFromInt(@intFromPtr(free_ram_start) + (@intFromPtr(ptr) - @intFromPtr(get_alloc_start())) / std.heap.pageSize());
    std.log.debug("descriptor addr: {*}", .{descriptor_addr});
    // Make sure the address is within our heap
    std.log.debug("descriptor addr: {*}, free_ram_start {*}", .{ descriptor_addr, free_ram_start });
    assert(@intFromPtr(descriptor_addr) >= @intFromPtr(free_ram_start) and @intFromPtr(descriptor_addr) < @intFromPtr(free_ram_start) + get_heap_size());
    var pages: [*]Page = @ptrCast(descriptor_addr);

    // Set all but the last page to be free
    while (pages[0].taken and !pages[0].last) {
        pages[0] = Page{ .taken = false, .last = false };
        pages = pages + 1;
    }

    // If the following occurs it is likely due to a double free
    assert(pages[0].last);

    // Here we have taken care of all previous pages and on the last page
    pages[0].taken = false;
    pages[0].last = false;
}

/// Allocate and zero a page or multiple pages
pub fn zero_alloc_page(pages: usize) std.mem.Allocator.Error![*]u8 {
    const ret = try alloc_page(pages);

    // Number of bytes to clear
    const size = (std.heap.pageSize * pages) / @sizeOf(u8);
    for (0..size) |i| {
        ret[i] = 0;
    }
}

/// Print table of page allocations
pub fn print_page_allocations() void {
    const num_pages = get_heap_size() / std.heap.pageSize();
    var beg: [*]Page = @ptrCast(free_ram_start);
    const end = beg + num_pages;
    const alloc_beg = 0;
    const alloc_end = alloc_beg + num_pages + std.heap.pageSize();

    common.putstr("\n");
    common.putstr("PAGE ALLOCATION TABLE\n");
    common.format_print("META: {*} -> {*}\n", .{ beg, end });
    common.format_print("PHYS: {x} -> {x}\n", .{ alloc_beg, alloc_end });
    common.putstr("--------------------------------\n");

    var num: usize = 0;
    while (@intFromPtr(beg) < @intFromPtr(end)) {
        if (beg[0].taken) {
            const start = @intFromPtr(beg);
            const memaddr = (start - @intFromPtr(free_ram_start)) + std.heap.pageSize();
            common.format_print("{x}\n => ", .{memaddr});
            while (true) {
                num += 1;
                if (beg[0].last) {
                    const inner_end = @intFromPtr(beg);
                    const inner_memaddr = (inner_end - @intFromPtr(free_ram_start)) + std.heap.pageSize() + std.heap.pageSize() + 1;
                    common.format_print("{x}: {d} pages.\n", .{ inner_memaddr, inner_end - start });
                    break;
                }
                beg += 1;
            }
        }
        beg += 1;
    }

    common.putstr("----------------------------------\n");
    common.format_print("Allocated: {d} pages ({d} bytes)\n", .{ num, num * std.heap.pageSize() });
    common.format_print("Free: {d} pages ({d} bytes)\n\n", .{ num_pages - num, (num_pages - num) * std.heap.pageSize() });
}

/// Print a visual representation of memory
pub fn print_page_graphic() void {
    const num_pages = get_heap_size() / std.heap.pageSize();
    var beg: [*]Page = @ptrCast(free_ram_start);
    const end = beg + num_pages;

    var num: usize = 0;
    while (@intFromPtr(beg) < @intFromPtr(end)) {
        if (beg[0].taken) {
            while (true) {
                num += 1;
                if (beg[0].last) {
                    common.putchar('L');
                    break;
                } else {
                    common.putchar('T');
                }
                beg += 1;
            }
        } else {
            common.putchar('.');
        }
        beg += 1;
    }
    common.putchar('\n');
}
