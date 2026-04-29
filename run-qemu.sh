#!/bin/bash
# Simple QEMU launcher with status messages

echo "Starting Kolos in QEMU..."
echo "========================================" 
echo "IMPORTANT: After the '> ' prompt appears:"
echo "  1. Type your command (e.g., 'help')"
echo "  2. Press ENTER"
echo ""
echo "If typing doesn't work, the issue is:"
echo "  - Terminal not passing input to QEMU"
echo "  - Try: echo 'help' | ./run-qemu.sh"
echo ""
echo "Exit: Press Ctrl-A, then X"
echo "========================================" 
echo ""

# Build first
zig build -Dtarget-board=qemu 2>&1 | grep -v "^$" || true

# Run QEMU with verbose settings
exec qemu-system-riscv32 \
    -machine virt \
    -m 128M \
    -bios none \
    -kernel zig-out/bin/kolos-kernel-qemu \
    -nographic \
    -serial mon:stdio
