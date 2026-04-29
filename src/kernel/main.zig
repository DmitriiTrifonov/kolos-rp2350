// Kolos Microkernel - Main entry point for RP2350 RISC-V
const std = @import("std");
const root = @import("root");
const boot = root.boot;
const hal = root.hal;
const memory = @import("memory.zig");
const scheduler = @import("scheduler.zig");
const ipc = @import("ipc.zig");
const syscall = @import("syscall.zig");
const trap = @import("trap.zig");
const init = root.init;

pub const std_options = struct {
    pub const log_level = .debug;
    pub const logFn = log;
};

// Kernel panic handler
pub const panic = boot.panic;

var kernel_heap: memory.KernelHeap = undefined;

// Process stacks (4KB each)
var init_stack: [4096]u8 align(16) = undefined;
var test_stack: [4096]u8 align(16) = undefined;
var idle_stack: [4096]u8 align(16) = undefined;

pub export fn kernel_main() noreturn {
    // VERY EARLY DEBUG - write directly to UART
    const uart_base: usize = if (@import("build_options").is_qemu) 0x10000000 else 0x40070000;
    const uart_ptr: *volatile u32 = @ptrFromInt(uart_base);
    
    // Write "K" to UART to show we got here
    uart_ptr.* = 'K';
    uart_ptr.* = '\n';
    
    // Initialize HAL (clocks, GPIO, etc.)
    uart_ptr.* = '1';
    hal.init();
    uart_ptr.* = '2';
    
    // Initialize trap handling (interrupts and system calls)
    uart_ptr.* = '3';
    trap.Trap.init();
    uart_ptr.* = '4';
    
    // Initialize timer for preemptive scheduling (10ms timeslice)
    uart_ptr.* = '5';
    const TICK_INTERVAL_US = 10000; // 10 milliseconds
    hal.Timer.init(TICK_INTERVAL_US);
    uart_ptr.* = '6';
    
    // Initialize kernel heap
    uart_ptr.* = '7';
    kernel_heap = memory.KernelHeap.init();
    uart_ptr.* = '8';
    
    // Initialize scheduler
    uart_ptr.* = '9';
    scheduler.init(kernel_heap.allocator());
    uart_ptr.* = 'A';
    
    // Initialize IPC subsystem
    uart_ptr.* = 'B';
    ipc.init(kernel_heap.allocator());
    uart_ptr.* = 'C';
    
    // Initialize system call interface
    uart_ptr.* = 'D';
    syscall.init();
    uart_ptr.* = 'E';
    uart_ptr.* = '\n';
    
    // Create initial userspace processes
    uart_ptr.* = 'F';
    
    // Create init process (PID 1)
    const init_entry = @intFromPtr(&init.init_main);
    const init_stack_top = @intFromPtr(&init_stack) + init_stack.len;
    _ = scheduler.create_process(init_entry, init_stack_top, 0, "init") catch {
        uart_ptr.* = 'X';
        @panic("Failed to create init process");
    };
    uart_ptr.* = 'G';
    
    // Create idle process (runs when nothing else is ready)
    const idle_entry = @intFromPtr(&init.idle_main);
    const idle_stack_top = @intFromPtr(&idle_stack) + idle_stack.len;
    _ = scheduler.create_process(idle_entry, idle_stack_top, 0, "idle") catch {
        uart_ptr.* = 'Y';
        @panic("Failed to create idle process");
    };
    uart_ptr.* = 'H';
    
    // Create test process to demonstrate multitasking (disabled for cleaner shell experience)
    // const test_entry = @intFromPtr(&init.test_process_main);
    // const test_stack_top = @intFromPtr(&test_stack) + test_stack.len;
    // _ = scheduler.create_process(test_entry, test_stack_top, 0, "test") catch {
    //     uart_ptr.* = 'Z';
    //     @panic("Failed to create test process");
    // };
    uart_ptr.* = 'I';
    
    log_info("Created initial processes", .{});
    log_info("Kolos microkernel initialized on RP2350 RISC-V", .{});
    log_info("Available RAM: {} bytes", .{memory.available_memory()});
    
    uart_ptr.* = 'J';
    uart_ptr.* = '\n';
    
    // Start scheduler (never returns)
    scheduler.start();
    
    unreachable;
}

fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = level;
    _ = scope;
    _ = format;
    _ = args;
    // TODO: Implement logging via UART when driver is ready
}

fn log_info(comptime format: []const u8, args: anytype) void {
    _ = format;
    _ = args;
    // Disabled for now to avoid std library issues
}
