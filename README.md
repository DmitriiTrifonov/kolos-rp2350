# Kolos - Microkernel OS for RP2350 RISC-V

A lightweight microkernel operating system built with Zig and MicroZig, targeting the RP2350's RISC-V Hazard3 cores on the PicoCalc device.

## Features

- **Microkernel Architecture**: Minimal kernel with services running in userspace
- **RISC-V Support**: Specifically targets RP2350's Hazard3 RISC-V cores
- **Message-Passing IPC**: Clean inter-process communication via message queues
- **Memory Management**: Page allocator for userspace and kernel heap management
- **Preemptive Scheduler**: Round-robin scheduling with timer-based preemption
- **Interrupt Handling**: Full RISC-V trap/interrupt support for system calls and hardware interrupts
- **Context Switching**: Hardware context switching between processes
- **System Call Interface**: Well-defined syscall API for userspace via ecall instruction
- **Hardware Abstraction**: HAL for RP2350 peripherals (UART, GPIO, Clocks, SPI, I2C, Timer)
- **PicoCalc Support**: Display (320x320 ST7789) and Keyboard (67-key I2C) drivers

## Architecture

### Kernel Components

- **Boot** (`src/boot/`): Startup code and hardware initialization
- **Kernel** (`src/kernel/`): Core microkernel functionality
  - Memory management (heap and page allocation)
  - Process scheduler with context switching
  - Trap handling (interrupts and exceptions)
  - IPC (message-passing)
  - System call interface
- **HAL** (`src/hal/`): Hardware abstraction for RP2350 (UART, GPIO, SPI, I2C, Timer)
- **Drivers** (`src/drivers/`): Userspace device drivers (UART, Display, Keyboard)
- **Init** (`src/init.zig`): Initial userspace processes (init, idle, test)

### Project Structure

```
kolos-rp2350/
├── build.zig           # MicroZig build configuration
├── build.zig.zon       # Dependencies
├── src/
│   ├── boot/
│   │   ├── start.zig   # Boot/startup code
│   │   └── linker.ld   # Linker script for RP2350
│   ├── kernel/
│   │   ├── main.zig    # Kernel entry point
│   │   ├── memory.zig  # Memory management
│   │   ├── scheduler.zig  # Process scheduler
│   │   ├── trap.zig    # Trap/interrupt handling
│   │   ├── ipc.zig     # Message-passing IPC
│   │   └── syscall.zig # System call interface
│   ├── hal/
│   │   └── rp2350.zig  # RP2350 HAL (UART, GPIO, SPI, I2C, Timer)
│   ├── drivers/
│   │   ├── uart_driver.zig  # UART driver service
│   │   ├── display_driver.zig  # ST7789 display driver
│   │   └── keyboard_driver.zig  # I2C keyboard driver
│   └── init.zig        # Initial userspace processes
└── LICENSE
```

## System Calls

The microkernel provides the following system calls (invoked via RISC-V `ecall` instruction):

- `sys_yield`: Yield CPU to other processes (cooperative multitasking)
- `sys_send`: Send IPC message to endpoint
- `sys_receive`: Receive IPC message from endpoint
- `sys_create_endpoint`: Create new IPC endpoint
- `sys_destroy_endpoint`: Destroy IPC endpoint
- `sys_allocate_pages`: Allocate memory pages
- `sys_free_pages`: Free memory pages
- `sys_exit`: Terminate current process
- `sys_create_process`: Create new process (future)

## Building

### Prerequisites

- Zig compiler (latest stable)
- MicroZig framework

### Build Steps

1. Fetch dependencies:
```bash
zig build --fetch
```

2. Update the MicroZig dependency hash in `build.zig.zon` if needed

3. Build the firmware:
```bash
zig build
```

This will generate:
- `zig-out/bin/kolos-kernel.uf2` - UF2 format for flashing to RP2350
- `zig-out/bin/kolos-kernel` - ELF executable for debugging
- `zig-out/bin/kolos-kernel.bin` - Raw binary
- `zig-out/bin/kolos-kernel.hex` - Intel HEX format

## Testing in QEMU

You can test the kernel in QEMU without hardware:

### Build for QEMU

```bash
zig build -Dtarget-board=qemu
```

This generates:
- `zig-out/bin/kolos-kernel-qemu` - QEMU-compatible ELF
- `zig-out/bin/kolos-kernel-qemu.bin` - Raw binary for QEMU

### Run in QEMU

> **📝 Note:** Interactive keyboard input works best with the expect wrapper.  
> See [TERMINAL_GUIDE.md](TERMINAL_GUIDE.md) for terminal compatibility details.

**Recommended: Interactive with expect wrapper**
```bash
./run-qemu-interactive.exp
```
✅ Works reliably in iTerm, Ghostty, and all terminal emulators.  
Exit: Press `Ctrl-A`, then `X`

**Alternative: Automated testing**
```bash
./test-shell.sh
```
Runs scripted commands and exits automatically.

**Manual methods:**
```bash
# Direct QEMU (may have keyboard issues in some terminals)
qemu-system-riscv32 \
    -machine virt -m 128M -bios none \
    -kernel zig-out/bin/kolos-kernel-qemu \
    -nographic -serial mon:stdio

# Piped commands (always works)
echo -e "help\ninfo\nps" | qemu-system-riscv32 \
    -machine virt -m 128M -bios none \
    -kernel zig-out/bin/kolos-kernel-qemu \
    -nographic -serial mon:stdio
```

### Interactive Shell

Once running in QEMU, you'll see the Kolos shell prompt:

```
> 
```

Try these commands:
- `help` - Show available commands
- `info` - Display system information
- `ps` - List running processes
- `echo <text>` - Echo text back
- `clear` - Clear screen (ANSI escape codes)

**Example session:**
```
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

> echo Hello from Kolos!
Hello from Kolos!
```

### QEMU vs Hardware Differences

| Feature | QEMU | RP2350 |
|---------|------|--------|
| Memory Layout | 0x80000000 (RAM) | 0x10000000 (Flash XIP) + 0x20000000 (SRAM) |
| UART | NS16550A @ 0x10000000 | PL011 @ 0x40070000 |
| Timer | CLINT @ 0x02000000 (10 MHz) | Memory-mapped @ 0x40054000 (1 MHz) |
| Clocks | Not needed | Requires XOSC + PLL setup |

## PicoCalc Hardware

Kolos is designed specifically for the ClockworkPi PicoCalc:

- **Display**: 320x320 IPS LCD (ST7789 controller via SPI)
- **Keyboard**: 67-key QWERTY with backlight (STM32-based I2C controller at 0x55)
- **CPU**: RP2350 RISC-V Hazard3 dual-core @ 150MHz
- **RAM**: 520KB SRAM
- **Storage**: 4MB Flash + SD card support
- **Power**: Dual 18650 battery system

### Hardware Interfaces

- SPI0 for display communication
- I2C0 for keyboard (STM32 manages keyboard matrix and backlight)
- UART0 for debug output
- GPIO for various control signals

## Flashing to PicoCalc

1. Hold the BOOTSEL button while powering on the PicoCalc
2. The device will appear as a USB mass storage device
3. Copy `kolos-kernel.uf2` to the device
4. The device will automatically reboot and run the OS

## Memory Layout

- **Flash (XIP)**: 0x10000000 - 0x10400000 (4MB)
  - Kernel code and read-only data
- **SRAM**: 0x20000000 - 0x20080000 (512KB)
  - Kernel heap: 64KB
  - Kernel stack: 16KB
  - User space: Remaining RAM

## Scheduler & Multitasking

Kolos implements a preemptive round-robin scheduler with the following features:

- **Preemptive Scheduling**: Timer interrupts (10ms timeslice) trigger automatic process switching
- **Context Switching**: Full CPU context (registers) saved and restored on every switch
- **Process States**: ready, running, blocked, waiting_for_message, terminated
- **Cooperative Yield**: Processes can voluntarily yield via `sys_yield` syscall
- **Idle Process**: Runs when no other processes are ready, uses WFI instruction for power saving

### Interrupt Handling

The kernel handles RISC-V machine mode interrupts and exceptions:

- **Timer Interrupt**: Triggers preemptive scheduling every 10ms
- **System Calls**: Handled via ecall exception, args passed in registers a0-a7
- **External Interrupts**: Framework in place for peripheral interrupts (future)
- **Exceptions**: Trap handler catches illegal instructions, faults, etc.

## Development Status

Current implementation includes:

- [x] Boot code for RISC-V
- [x] Memory management (heap and pages)
- [x] IPC message-passing
- [x] Preemptive scheduler with round-robin scheduling
- [x] Context switching between processes
- [x] Trap/interrupt handling for RISC-V
- [x] Timer support for preemptive multitasking (10ms timeslice)
- [x] System call interface via ecall instruction
- [x] RP2350 HAL (UART, GPIO, Clocks, SPI, I2C, Timer)
- [x] UART driver framework
- [x] Display driver for ST7789 (320x320 SPI)
- [x] Keyboard driver for I2C-based QWERTY keyboard
- [x] Init process and basic shell framework
- [x] Idle process for power management

TODO:

- [ ] Full syscall implementations (message copying, validation)
- [ ] Dynamic process creation from userspace
- [ ] Additional device drivers (SD card, audio, PSRAM)
- [ ] Filesystem support
- [ ] Full interactive shell
- [ ] More example userspace applications

## License

Licensed under the MIT License. See LICENSE file for details.

## About

Kolos is designed as an educational microkernel OS to demonstrate microkernel architecture principles on embedded RISC-V hardware. It showcases:

- Separation of mechanism and policy
- Minimal kernel with maximal flexibility
- Message-based IPC for service communication
- Clean hardware abstraction
