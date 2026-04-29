// Boot code for RP2350 RISC-V Hazard3 cores and QEMU virt
const std = @import("std");

// Symbols from linker script
extern const _sdata: u8;
extern const _edata: u8;
extern const _sidata: u8;
extern const _sbss: u8;
extern const _ebss: u8;
extern const _stack_top: u8;

// Entry point is in start.S (assembly), which calls this function
pub export fn _start_zig() noreturn {
    // VERY EARLY DEBUG - write to UART before anything else
    const uart_base: usize = 0x10000000; // QEMU UART
    const uart_ptr: *volatile u32 = @ptrFromInt(uart_base);
    uart_ptr.* = 'Z'; // Write 'Z' to show we got to _start_zig
    
    // Initialize data section
    @call(.always_inline, init_data, .{});
    
    uart_ptr.* = 'D'; // Data initialized

    // Initialize BSS section
    @call(.always_inline, init_bss, .{});
    
    uart_ptr.* = 'B'; // BSS initialized

    // Jump to kernel main
    kernel_main();

    unreachable;
}

fn init_data() void {
    // For QEMU, data is already in RAM (no flash copy needed)
    // Skip data initialization for now
    return;
}

fn init_bss() void {
    const bss_start = @as([*]u8, @ptrCast(@constCast(&_sbss)));
    const bss_end = @as([*]u8, @ptrCast(@constCast(&_ebss)));
    
    const len = @intFromPtr(bss_end) - @intFromPtr(bss_start);
    if (len > 0) {
        @memset(bss_start[0..len], 0);
    }
}

// Import kernel_main from kernel module
extern fn kernel_main() noreturn;

// Default panic handler
pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = message;
    // TODO: Output to UART when driver is ready
    while (true) {
        asm volatile ("wfi"); // Wait for interrupt (low power)
    }
}
