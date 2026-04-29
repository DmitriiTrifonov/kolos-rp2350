// UART driver as userspace service (microkernel architecture)
const std = @import("std");
const syscall = @import("../kernel/syscall.zig");
const ipc = @import("../kernel/ipc.zig");

const UART_BASE: usize = 0x40070000;
const UART_DR: usize = 0x00;
const UART_FR: usize = 0x18;

// UART driver message types
pub const UartCommand = enum(u32) {
    write_byte,
    write_string,
    read_byte,
    read_line,
};

pub const UartMessage = struct {
    command: UartCommand,
    data: [252]u8, // Leave room for command
};

// Driver entry point
pub fn uart_driver_main() noreturn {
    // Create IPC endpoint for this service
    const endpoint_id = syscall.UserAPI.create_endpoint() orelse {
        syscall.UserAPI.exit();
    };
    
    // Main service loop
    while (true) {
        // Wait for messages
        if (syscall.UserAPI.receive(endpoint_id)) |msg| {
            handle_message(&msg);
        }
        
        // Yield to other processes
        syscall.UserAPI.yield();
    }
}

fn handle_message(msg: *const ipc.Message) void {
    const data = msg.get_data();
    if (data.len < 4) return;
    
    const command: UartCommand = @enumFromInt(@as(u32, @intCast(data[0])) |
                                              (@as(u32, @intCast(data[1])) << 8) |
                                              (@as(u32, @intCast(data[2])) << 16) |
                                              (@as(u32, @intCast(data[3])) << 24));
    
    switch (command) {
        .write_byte => {
            if (data.len >= 5) {
                write_byte(data[4]);
            }
        },
        .write_string => {
            if (data.len > 4) {
                write_string(data[4..]);
            }
        },
        .read_byte => {
            _ = read_byte();
        },
        .read_line => {
            // Not implemented yet
        },
    }
}

fn write_byte(byte: u8) void {
    const ptr: *volatile u32 = @ptrFromInt(UART_BASE + UART_DR);
    const fr_ptr: *volatile u32 = @ptrFromInt(UART_BASE + UART_FR);
    
    // Wait for TX FIFO not full
    while ((fr_ptr.* & (1 << 5)) != 0) {}
    ptr.* = byte;
}

fn write_string(str: []const u8) void {
    for (str) |c| {
        write_byte(c);
    }
}

fn read_byte() ?u8 {
    const ptr: *volatile u32 = @ptrFromInt(UART_BASE + UART_DR);
    const fr_ptr: *volatile u32 = @ptrFromInt(UART_BASE + UART_FR);
    
    // Check if RX FIFO is empty
    if ((fr_ptr.* & (1 << 4)) != 0) {
        return null;
    }
    return @intCast(ptr.* & 0xFF);
}
