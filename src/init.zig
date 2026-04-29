// Init process for Kolos microkernel
// This is the first userspace process that runs
const std = @import("std");
const root = @import("root");
const syscall = root.syscall;
const hal = root.hal;

// Simple UART output for init process
fn uart_putc(c: u8) void {
    // Direct UART access (QEMU)
    const uart_base: usize = 0x10000000;
    const uart_ptr: *volatile u32 = @ptrFromInt(uart_base);
    uart_ptr.* = c;
}

fn uart_getc() ?u8 {
    // Direct UART access for reading (QEMU NS16550A)
    const uart_base: usize = 0x10000000;
    const lsr_ptr: *allowzero volatile u8 = @ptrFromInt(uart_base + 5); // Line Status Register
    const data_ptr: *volatile u32 = @ptrFromInt(uart_base);
    
    // Check if data is available (LSR bit 0 = data ready)
    if ((lsr_ptr.* & 0x01) != 0) {
        return @truncate(data_ptr.*);
    }
    return null;
}

fn uart_puts(s: []const u8) void {
    for (s) |c| {
        uart_putc(c);
    }
}

fn uart_put_number(n: u32) void {
    var num = n;
    var digits: [10]u8 = undefined;
    var count: usize = 0;
    
    if (num == 0) {
        uart_putc('0');
        return;
    }
    
    while (num > 0) {
        digits[count] = @intCast((num % 10) + '0');
        num /= 10;
        count += 1;
    }
    
    while (count > 0) {
        count -= 1;
        uart_putc(digits[count]);
    }
}

/// Init process entry point
pub export fn init_main() noreturn {
    // VERY EARLY DEBUG - direct UART access
    const uart_base: usize = 0x10000000;
    const uart_ptr: *volatile u32 = @ptrFromInt(uart_base);
    uart_ptr.* = 'I';
    uart_ptr.* = 'N';
    uart_ptr.* = 'I';
    uart_ptr.* = 'T';
    uart_ptr.* = '\n';
    
    uart_puts("\r\n");
    uart_puts("========================================\r\n");
    uart_puts("Kolos Microkernel - RP2350 RISC-V\r\n");
    uart_puts("========================================\r\n");
    uart_puts("\r\n");
    
    // Get our process ID
    const pid = syscall.UserAPI.get_pid();
    uart_puts("Init process started (PID: ");
    uart_put_number(pid);
    uart_puts(")\r\n");
    
    // Create an IPC endpoint for communication
    if (syscall.UserAPI.create_endpoint()) |endpoint_id| {
        uart_puts("Created IPC endpoint: ");
        uart_put_number(endpoint_id);
        uart_puts("\r\n");
    }
    
    // Display hardware info
    uart_puts("\r\n");
    uart_puts("Platform: QEMU RISC-V virt machine\r\n");
    uart_puts("Target Hardware: RP2350 (ClockworkPi PicoCalc)\r\n");
    uart_puts("  CPU: RP2350 RISC-V Hazard3 @ 150MHz\r\n");
    uart_puts("  RAM: 520KB SRAM + 8MB PSRAM\r\n");
    uart_puts("  Display: 320x320 IPS (ST7789)\r\n");
    uart_puts("  Keyboard: 67-key QWERTY (I2C)\r\n");
    uart_puts("\r\n");
    
    // Simple shell loop
    uart_puts("Kolos Shell (type 'help' for commands)\r\n");
    uart_puts("Press Enter to see available commands\r\n");
    
    var input_buffer: [64]u8 = undefined;
    var input_pos: usize = 0;
    
    while (true) {
        uart_puts("\r\n> ");
        input_pos = 0;
        
        // Read a line of input
        while (true) {
            // Try to read a character (busy wait)
            if (uart_getc()) |c| {
                // Handle special characters
                if (c == '\r' or c == '\n') {
                    uart_puts("\r\n");
                    break;
                } else if (c == 127 or c == 8) { // Backspace or DEL
                    if (input_pos > 0) {
                        input_pos -= 1;
                        uart_puts("\x08 \x08"); // Backspace, space, backspace
                    }
                } else if (c >= 32 and c < 127) { // Printable characters
                    if (input_pos < input_buffer.len) {
                        input_buffer[input_pos] = c;
                        input_pos += 1;
                        uart_putc(c); // Echo
                    }
                }
            }
            // Don't yield here - busy wait for input
            // This keeps the shell responsive for keyboard input
        }
        
        // Process the command
        const cmd = input_buffer[0..input_pos];
        
        if (cmd.len == 0) {
            continue;
        } else if (std.mem.eql(u8, cmd, "help")) {
            uart_puts("Available commands:\r\n");
            uart_puts("  help     - Show this help message\r\n");
            uart_puts("  info     - Show system information\r\n");
            uart_puts("  ps       - List processes\r\n");
            uart_puts("  clear    - Clear screen\r\n");
            uart_puts("  echo     - Echo arguments\r\n");
        } else if (std.mem.eql(u8, cmd, "info")) {
            uart_puts("Kolos Microkernel v0.1\r\n");
            uart_puts("Running on QEMU RISC-V virt machine\r\n");
            uart_puts("Target: RP2350 (ClockworkPi PicoCalc)\r\n");
        } else if (std.mem.eql(u8, cmd, "ps")) {
            uart_puts("PID  State    Name\r\n");
            uart_puts("---  -------  ----\r\n");
            uart_puts("1    running  init\r\n");
            uart_puts("2    ready    idle\r\n");
        } else if (std.mem.eql(u8, cmd, "clear")) {
            uart_puts("\x1b[2J\x1b[H"); // ANSI clear screen and home
        } else if (std.mem.startsWith(u8, cmd, "echo ")) {
            uart_puts(cmd[5..]);
            uart_puts("\r\n");
        } else {
            uart_puts("Unknown command: ");
            uart_puts(cmd);
            uart_puts("\r\n");
            uart_puts("Type 'help' for available commands\r\n");
        }
    }
}

/// Idle process - runs when no other processes are ready
pub export fn idle_main() noreturn {
    while (true) {
        // Wait for interrupt
        asm volatile ("wfi");
    }
}

/// Test process that demonstrates multitasking
pub export fn test_process_main() noreturn {
    var counter: u32 = 0;
    
    while (true) {
        counter += 1;
        
        if (counter % 50 == 0) {
            uart_puts("[Test Process] Counter: ");
            uart_put_number(counter);
            uart_puts("\r\n");
        }
        
        syscall.UserAPI.yield();
        hal.Delay.delay_ms(200);
    }
}
