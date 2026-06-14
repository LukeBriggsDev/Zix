ENTRY(boot)

PHDRS {
    text       PT_LOAD FLAGS(5);
    rodata     PT_LOAD FLAGS(4);
    data       PT_LOAD FLAGS(6);
    dbg_info   PT_LOAD FLAGS(4);
    dbg_abbrev PT_LOAD FLAGS(4);
    dbg_str    PT_LOAD FLAGS(4);
    dbg_line   PT_LOAD FLAGS(4);
    dbg_ranges PT_LOAD FLAGS(4);
}

SECTIONS {
    . = 0x80200000;
    kernel_base = .;

    .text : {
        KEEP(*(.text.boot));
        *(.text .text.*);
    } :text

    .rodata : ALIGN(4096) {
        *(.rodata .rodata.*);
    } :rodata

    .data : ALIGN(4096) {
        *(.data .data.*);
    } :data

    .bss : ALIGN(4096) {
        __bss = .;
        *(.bss .bss.* .sbss .sbss.*);
        __bss_end = .;
    } :data

    /* Debug sections with VMA=0 so LLD emits section-relative DWARF offsets.
       One segment per section keeps MemSiz == FileSiz for correct ELF loading.
       LMAs are packed after .bss in physical memory; symbols track exact addresses. */
    _dbg_lma = ALIGN(ADDR(.bss) + SIZEOF(.bss), 4096);

    .debug_info_start   = _dbg_lma;
    .debug_info   0 : AT(_dbg_lma) { KEEP(*(.debug_info)) } :dbg_info
    .debug_info_end     = _dbg_lma + SIZEOF(.debug_info);

    .debug_abbrev_start = _dbg_lma + SIZEOF(.debug_info);
    .debug_abbrev 0 : AT(_dbg_lma + SIZEOF(.debug_info)) { KEEP(*(.debug_abbrev)) } :dbg_abbrev
    .debug_abbrev_end   = _dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev);

    .debug_str_start    = _dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev);
    .debug_str    0 : AT(_dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev)) { KEEP(*(.debug_str)) } :dbg_str
    .debug_str_end      = _dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev) + SIZEOF(.debug_str);

    .debug_line_start   = _dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev) + SIZEOF(.debug_str);
    .debug_line   0 : AT(_dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev) + SIZEOF(.debug_str)) { KEEP(*(.debug_line)) } :dbg_line
    .debug_line_end     = _dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev) + SIZEOF(.debug_str) + SIZEOF(.debug_line);

    .debug_ranges_start = _dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev) + SIZEOF(.debug_str) + SIZEOF(.debug_line);
    .debug_ranges 0 : AT(_dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev) + SIZEOF(.debug_str) + SIZEOF(.debug_line)) { KEEP(*(.debug_ranges)) } :dbg_ranges
    .debug_ranges_end   = _dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev) + SIZEOF(.debug_str) + SIZEOF(.debug_line) + SIZEOF(.debug_ranges);

    . = _dbg_lma + SIZEOF(.debug_info) + SIZEOF(.debug_abbrev) + SIZEOF(.debug_str) + SIZEOF(.debug_line) + SIZEOF(.debug_ranges);
    . = ALIGN(4096);
    . += 8 * 1024 * 1024; /* 8MB stack */
    __stack_top = .;

    . = ALIGN(4096);
    free_ram_start = .;
    . += 64 * 1024 * 1024; /* 64MB */
    free_ram_end = .;
}
