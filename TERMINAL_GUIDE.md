# QEMU Keyboard Input - Terminal Compatibility Guide

## ✅ Working Solutions

### Option 1: Expect Wrapper (RECOMMENDED for iTerm/Ghostty)

```bash
./run-qemu-interactive.exp
```

**Why this works:**
- `expect` properly manages terminal I/O between your shell and QEMU
- Handles all the quirks of `-serial mon:stdio`
- Works reliably across different terminal emulators

**Exit:** Press `Ctrl-A`, then `X`

---

### Option 2: Scripted/Piped Input (ALWAYS WORKS)

```bash
./test-shell.sh
```

Or manually:
```bash
echo -e "help\ninfo\nps\necho Hello!" | \
  qemu-system-riscv32 -machine virt -m 128M -bios none \
  -kernel zig-out/bin/kolos-kernel-qemu -nographic -serial mon:stdio
```

**Why this works:**
- Input comes from file/pipe, not terminal
- No terminal I/O complications
- Perfect for automated testing

---

### Option 3: Direct QEMU (may have issues in some terminals)

```bash
qemu-system-riscv32 \
    -machine virt \
    -m 128M \
    -bios none \
    -kernel zig-out/bin/kolos-kernel-qemu \
    -nographic \
    -serial mon:stdio
```

**Why this might not work in iTerm/Ghostty:**
- QEMU monitor console uses Ctrl-A as escape sequence
- Some terminals don't properly forward these sequences
- Monitor multiplexing can interfere with character input

**If it works:** Exit with `Ctrl-A`, then `X`

---

## 🔍 Testing Your Setup

### Quick Test (works everywhere):
```bash
./test-shell.sh
```

Expected output:
```
> help
Available commands:
  help     - Show this help message
  [...]

> info  
Kolos Microkernel v0.1
[...]

> ps
PID  State    Name
---  -------  ----
1    running  init
2    ready    idle
```

### Interactive Test (if expect is installed):
```bash
./run-qemu-interactive.exp
```

Then type:
- `help`
- `info`
- `ps`
- `echo Hello World!`

---

## ❓ Why Terminal Emulators Differ

**The Issue:**
- QEMU's `-serial mon:stdio` creates a "monitor console" multiplexed with serial
- Uses `Ctrl-A` as escape character
- Different terminals handle this differently:
  - **iTerm2**: May not forward Ctrl-A sequences properly
  - **Ghostty**: Similar issues with escape sequence handling
  - **gnome-terminal**: Usually works
  - **Terminal.app**: Usually works
  - **tmux/screen**: Extra layer of escape sequences

**The Solution:**
- Use `expect` wrapper to properly handle I/O
- Or use scripted input which bypasses terminal issues

---

## 📊 Compatibility Matrix

| Method | iTerm | Ghostty | Terminal.app | Notes |
|--------|-------|---------|--------------|-------|
| `run-qemu-interactive.exp` | ✅ | ✅ | ✅ | Recommended |
| `test-shell.sh` (scripted) | ✅ | ✅ | ✅ | Always works |
| Direct QEMU | ❓ | ❓ | ✅ | YMMV |
| Piped input | ✅ | ✅ | ✅ | Always works |

---

## 🛠️ Troubleshooting

### "I type but nothing appears"

**Try this:**
```bash
# Test 1: Verify kernel works with piped input
echo "help" | qemu-system-riscv32 -machine virt -m 128M -bios none \
  -kernel zig-out/bin/kolos-kernel-qemu -nographic -serial mon:stdio

# Test 2: Use expect wrapper
./run-qemu-interactive.exp

# Test 3: Check if expect is installed
which expect  # Should show: /usr/bin/expect
```

### "Characters appear double (hh instead of h)"

This shouldn't happen with our code, but if it does:
```bash
# Check terminal settings
stty -a | grep echo
# Should show: -echo (echo is OFF)
```

### "Can't exit QEMU"

From another terminal:
```bash
killall qemu-system-riscv32
```

---

## ✨ Verified Working Commands

These commands have been tested and work:

```bash
# In QEMU shell prompt:
help           # Show commands
info           # System info
ps             # List processes  
echo Hello!    # Echo text
clear          # Clear screen (ANSI codes)
```

Example session:
```
> help
Available commands:
  help     - Show this help message
  info     - Show system information
  ps       - List processes
  clear    - Clear screen
  echo     - Echo arguments

> echo Testing keyboard input!
Testing keyboard input!
```

---

## 🎯 Summary

**For interactive use in iTerm/Ghostty:**
```bash
./run-qemu-interactive.exp
```

**For automated testing:**
```bash
./test-shell.sh
```

**Both methods are confirmed working! 🎉**
