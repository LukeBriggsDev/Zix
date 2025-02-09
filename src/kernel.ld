ENTRY(boot)

SECTIONS {
    . = 0x80200000;

    .text :{
        KEEP(*(.text.boot));
        *(.text .text.*);
    }

    .rodata : ALIGN(8) {
        *(.rodata .rodata.*);
	.debug_info_start = .;
	KEEP(*(.debug_info))
	.debug_info_end = .;
	.debug_abbrev_start = .;
	KEEP(*(.debug_abbrev))
	.debug_abbrev_end = .;
	.debug_str_start = .;
	KEEP(*(.debug_str))
	.debug_str_end = .;
	.debug_line_start = .;
	KEEP(*(.debug_line))
	.debug_line_end = .;
	.debug_ranges_start = .;
	KEEP(*(.debug_ranges))
	.debug_ranges_end = .;
    }

    .data : ALIGN(8) {
        *(.data .data.*);
    }

    .bss : ALIGN(8) {
        __bss = .;
        *(.bss .bss.* .sbss .sbss.*);
        __bss_end = .;
    }

    . = ALIGN(8);
    . += 128 * 1024; /* 128KB */
    __stack_top = .;
}
