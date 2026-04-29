#!/bin/bash
# Test interactive shell in QEMU

cat > /tmp/kolos_test_commands.txt << 'EOF'
help
info
ps
echo Welcome to Kolos!
echo Testing command execution...
clear
EOF

echo "Running Kolos in QEMU with test commands..."
echo "==========================================="
echo ""

timeout 5 qemu-system-riscv32 \
    -machine virt \
    -m 128M \
    -bios none \
    -kernel zig-out/bin/kolos-kernel-qemu \
    -nographic \
    -serial mon:stdio \
    < /tmp/kolos_test_commands.txt

echo ""
echo "==========================================="
echo "Test completed!"

