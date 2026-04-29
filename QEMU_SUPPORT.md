# Kolos QEMU Support - Summary

## ✅ What We Accomplished

We successfully added full QEMU emulation support to the Kolos microkernel, allowing development and testing without hardware.

### Key Features Implemented

1. **QEMU Build Target**
   - Separate build configuration: `zig build -Dtarget-board=qemu`
   - Platform-specific code via `build_options.is_qemu`
   - Dedicated linker script for QEMU virt machine memory layout

2. **Hardware Abstraction**
   - UART driver supports both NS16550A (QEMU) and PL011 (RP2350)
   - Timer supports both CLINT (QEMU @ 10MHz) and RP2350 (@ 1MHz)
   - Conditional clock initialization (skipped on QEMU)

3. **Boot Sequence**
   - Pure assembly entry point (`_start` in start.S)
   - Proper stack initialization before calling Zig code
   - Renamed `_start_rust` → `_start_zig` for accuracy

4. **Interactive Shell**
   - Full keyboard input support via UART
   - Command-line editing (backspace, echo)
   - Built-in commands: help, info, ps, echo, clear
   - Works both interactively and via piped/scripted input

### Files Created

- `src/boot/start.S` - Assembly entry point
- `src/boot/linker-qemu.ld` - QEMU memory layout
- `run-qemu.sh` - Interactive QEMU launcher
- `test-shell.sh` - Automated shell testing script
- `test-shell-expect.exp` - Expect-based testing (optional)

### Files Modified

- `build.zig` - Added QEMU build target and run step
- `src/boot/start.zig` - Renamed to `_start_zig()`, added early debugging
- `src/hal/rp2350.zig` - Platform-aware UART/Timer, added QEMU support
- `src/kernel/main.zig` - Debug output during initialization
- `src/kernel/scheduler.zig` - Debug output for scheduler start
- `src/init.zig` - Added UART input, interactive shell, command parser
- `README.md` - Comprehensive QEMU documentation

## 🚀 Usage

### Quick Start

**Interactive (recommended):**
```bash
./run-qemu-interactive.exp
```

**Automated Testing:**
```bash
./test-shell.sh
```

### Build for QEMU
```bash
zig build -Dtarget-board=qemu
```

### Run Interactively

**Option 1: Using expect wrapper (best for iTerm/Ghostty)**
```bash
./run-qemu-interactive.exp
```
- Proper terminal handling
- Exit: Type `quit` or press `Ctrl-C`

**Option 2: Direct QEMU with monitor**
```bash
qemu-system-riscv32 -machine virt -m 128M -bios none \
  -kernel zig-out/bin/kolos-kernel-qemu -nographic -serial mon:stdio
```
- Exit: Press `Ctrl-A`, then `X`
- Note: May have input issues in some terminals

**Option 3: Direct QEMU without monitor**
```bash
qemu-system-riscv32 -machine virt -m 128M -bios none \
  -kernel zig-out/bin/kolos-kernel-qemu -nographic -serial stdio
```
- Exit: Press `Ctrl-C`
- Simpler but no QEMU monitor access

### Run Automated Tests
```bash
./test-shell.sh
```

### Pipe Commands
```bash
echo -e "help\ninfo\nps\necho Hello!" | \
  qemu-system-riscv32 -machine virt -m 128M -bios none \
  -kernel zig-out/bin/kolos-kernel-qemu -nographic -serial mon:stdio
```

## 🎮 Interactive Shell Commands

| Command | Description |
|---------|-------------|
| `help` | Show available commands |
| `info` | Display system information |
| `ps` | List running processes |
| `echo <text>` | Echo text back |
| `clear` | Clear screen (ANSI codes) |

## 🔧 Technical Details

### Memory Layout

**QEMU:**
- RAM: 0x80000000 - 0x88000000 (128MB)
- All code and data in RAM

**RP2350:**
- Flash (XIP): 0x10000000 - 0x10400000 (4MB)
- SRAM: 0x20000000 - 0x20080000 (512KB)

### UART Differences

**QEMU (NS16550A):**
- Base: 0x10000000
- Data: Base + 0
- LSR: Base + 5 (bit 0 = data ready)
- No initialization needed

**RP2350 (PL011):**
- Base: 0x40070000
- Requires clock setup, GPIO muxing
- Different register layout

### Timer Differences

**QEMU (CLINT):**
- Base: 0x02000000
- mtime: Base + 0xbff8
- mtimecmp: Base + 0x4000
- Frequency: 10 MHz

**RP2350:**
- Base: 0x40054000
- mtime: Base + 0x00
- mtimecmp: Base + 0x08
- Frequency: 1 MHz

## 📊 Working Features

| Feature | Status |
|---------|--------|
| Boot sequence | ✅ Working |
| HAL initialization | ✅ Working |
| Trap/interrupt setup | ✅ Working |
| Timer initialization | ✅ Working |
| Memory management | ✅ Working |
| Process scheduler | ✅ Working |
| IPC system | ✅ Working |
| System calls | ✅ Working |
| Process creation | ✅ Working |
| Context switching | ✅ Working |
| UART output | ✅ Working |
| UART input (keyboard) | ✅ Working |
| Interactive shell | ✅ Working |
| Command parsing | ✅ Working |

## 🐛 Known Limitations

1. **Single Process Active** - Init process busy-waits for input (no UART interrupts yet)
2. **No Preemption During Input** - Timer interrupts not enabled during shell loop
3. **ANSI Codes** - `clear` command shows escape codes in piped mode
4. **Limited Commands** - Shell is minimal, just for demonstration

## 🔧 Troubleshooting

### Keyboard Input Not Working in Terminal

**Symptom:** You can see output but typing doesn't work in iTerm/Ghostty/other terminals.

**Solution:** Use the expect wrapper script:
```bash
./run-qemu-interactive.exp
```

**Why:** Different terminal emulators handle QEMU's serial port differently:
- `-serial mon:stdio` multiplexes QEMU monitor with serial (can interfere)
- `-serial stdio` is direct but some terminals don't handle it well
- `expect` wrapper properly manages the terminal I/O

**Alternative:** Use piped/scripted input which always works:
```bash
echo -e "help\ninfo\nps" | qemu-system-riscv32 ... -serial stdio
```

### QEMU Won't Exit

**Symptom:** Ctrl-C doesn't work to exit QEMU.

**Solutions:**
- With `-serial mon:stdio`: Press `Ctrl-A`, then `X`
- With `-serial stdio`: Press `Ctrl-C`
- With expect wrapper: Type `quit` or press `Ctrl-C`
- Last resort: From another terminal: `killall qemu-system-riscv32`

### Characters Appear Double

**Symptom:** Typing "h" shows "hh".

**Cause:** Both the terminal and the shell are echoing characters.

**Solution:** This shouldn't happen with our code, but if it does, check that:
- The init process is using `uart_putc(c)` to echo (not automatic)
- Terminal isn't in "local echo" mode

### No Output Visible

**Symptom:** QEMU runs but nothing appears.

**Check:**
1. Built for QEMU: `zig build -Dtarget-board=qemu`
2. Using correct kernel: `zig-out/bin/kolos-kernel-qemu`
3. Not running hardware build in QEMU by mistake

## 🔮 Future Improvements

1. **UART Interrupts** - Wake init process on incoming data
2. **More Commands** - Add memory stats, process management, etc.
3. **Multi-process Demo** - Show preemptive multitasking while shell runs
4. **File System** - Simple in-memory filesystem
5. **Driver Loading** - Load display/keyboard drivers as userspace processes

## 📝 Example Session

```
$ ./run-qemu.sh

Kolos Microkernel - RP2350 RISC-V
========================================

Init process started (PID: 1)
Created IPC endpoint: 1

Platform: QEMU RISC-V virt machine
Target Hardware: RP2350 (ClockworkPi PicoCalc)

Kolos Shell (type 'help' for commands)

> help
Available commands:
  help     - Show this help message
  info     - Show system information
  ps       - List processes
  clear    - Clear screen
  echo     - Echo arguments

> info
Kolos Microkernel v0.1
Running on QEMU RISC-V virt machine
Target: RP2350 (ClockworkPi PicoCalc)

> ps
PID  State    Name
---  -------  ----
1    running  init
2    ready    idle

> echo Hello, World!
Hello, World!

> (Press Ctrl-A, then X to exit)
```

## 🎯 Next Steps

1. Test on real RP2350 hardware (PicoCalc)
2. Implement display driver (ST7789)
3. Implement keyboard driver (I2C)
4. Add more userspace services
5. Build simple applications

---

**Result:** Kolos microkernel is now fully testable in QEMU with interactive keyboard input!
