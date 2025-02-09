#!/bin/bash
set -xue

# QEMU file path
QEMU=qemu-system-riscv64



# Start QEMU
$QEMU -machine virt -bios default -nographic -serial mon:stdio --no-reboot -kernel zig-out/bin/zix
