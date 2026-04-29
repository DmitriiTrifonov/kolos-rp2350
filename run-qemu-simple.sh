#!/bin/bash
# Simple QEMU runner - use with piped commands

# Build for QEMU
zig build -Dtarget-board=qemu 2>&1 | grep -v "^$" || true

echo ""
echo "========================================="
echo "Kolos QEMU - Simple Runner"
echo "========================================="
echo ""
echo "Usage:"
echo "  echo 'help' | $0"
echo "  echo -e 'help\\ninfo\\nps' | $0"
echo "  cat commands.txt | $0"
echo ""
echo "Exit: Ctrl-C"
echo "========================================="
echo ""

# Run QEMU - reads from stdin
qemu-system-riscv32 \
    -machine virt \
    -m 128M \
    -bios none \
    -kernel zig-out/bin/kolos-kernel-qemu \
    -nographic \
    -serial mon:stdio
