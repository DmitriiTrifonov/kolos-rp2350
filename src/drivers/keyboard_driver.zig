// Keyboard driver for PicoCalc (I2C STM32-based keyboard controller)
// Userspace driver service for microkernel architecture
const std = @import("std");
const syscall = @import("../kernel/syscall.zig");
const ipc = @import("../kernel/ipc.zig");

// I2C address for the STM32 keyboard controller
const KEYBOARD_I2C_ADDR: u8 = 0x55; // PicoCalc keyboard I2C address

// I2C peripheral base address
const I2C_BASE: usize = 0x40060000; // I2C0
const I2C_TAR: usize = 0x04;
const I2C_DATA_CMD: usize = 0x10;
const I2C_STATUS: usize = 0x70;

// Keyboard command types
pub const KeyboardCommand = enum(u32) {
    read_keys,
    set_backlight,
    get_status,
};

// Keyboard key mapping (67 keys)
pub const KeyCode = enum(u8) {
    KEY_NONE = 0,
    KEY_ESC,
    KEY_1,
    KEY_2,
    KEY_3,
    KEY_4,
    KEY_5,
    KEY_6,
    KEY_7,
    KEY_8,
    KEY_9,
    KEY_0,
    KEY_MINUS,
    KEY_EQUALS,
    KEY_BACKSPACE,
    KEY_TAB,
    KEY_Q,
    KEY_W,
    KEY_E,
    KEY_R,
    KEY_T,
    KEY_Y,
    KEY_U,
    KEY_I,
    KEY_O,
    KEY_P,
    KEY_LEFTBRACE,
    KEY_RIGHTBRACE,
    KEY_ENTER,
    KEY_LEFTCTRL,
    KEY_A,
    KEY_S,
    KEY_D,
    KEY_F,
    KEY_G,
    KEY_H,
    KEY_J,
    KEY_K,
    KEY_L,
    KEY_SEMICOLON,
    KEY_APOSTROPHE,
    KEY_GRAVE,
    KEY_LEFTSHIFT,
    KEY_BACKSLASH,
    KEY_Z,
    KEY_X,
    KEY_C,
    KEY_V,
    KEY_B,
    KEY_N,
    KEY_M,
    KEY_COMMA,
    KEY_DOT,
    KEY_SLASH,
    KEY_RIGHTSHIFT,
    KEY_LEFTALT,
    KEY_SPACE,
    KEY_CAPSLOCK,
    KEY_F1,
    KEY_F2,
    KEY_F3,
    KEY_F4,
    KEY_F5,
    KEY_F6,
    KEY_UP,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    _,
};

// Hardware access helpers
fn write_reg(addr: usize, value: u32) void {
    const ptr: *volatile u32 = @ptrFromInt(addr);
    ptr.* = value;
}

fn read_reg(addr: usize) u32 {
    const ptr: *volatile u32 = @ptrFromInt(addr);
    return ptr.*;
}

fn i2c_write_byte(byte: u8) void {
    // Wait for TX FIFO not full
    while ((read_reg(I2C_BASE + I2C_STATUS) & 0x02) == 0) {}
    write_reg(I2C_BASE + I2C_DATA_CMD, byte);
}

fn i2c_read_byte() u8 {
    // Send read command
    write_reg(I2C_BASE + I2C_DATA_CMD, 0x100); // Read bit set
    
    // Wait for RX FIFO not empty
    while ((read_reg(I2C_BASE + I2C_STATUS) & 0x08) == 0) {}
    return @intCast(read_reg(I2C_BASE + I2C_DATA_CMD) & 0xFF);
}

fn set_i2c_target(addr: u8) void {
    write_reg(I2C_BASE + I2C_TAR, addr);
}

// Keyboard driver functions
pub fn init_keyboard() void {
    // Set I2C target address for keyboard
    set_i2c_target(KEYBOARD_I2C_ADDR);
    
    // Initialize keyboard (send init command)
    i2c_write_byte(0x01); // Init command
}

pub fn read_key_state() [16]u8 {
    var key_state: [16]u8 = undefined;
    
    set_i2c_target(KEYBOARD_I2C_ADDR);
    
    // Request key state
    i2c_write_byte(0x10); // Read keys command
    
    // Read 16 bytes of key state data
    for (&key_state) |*byte| {
        byte.* = i2c_read_byte();
    }
    
    return key_state;
}

pub fn set_backlight(brightness: u8) void {
    set_i2c_target(KEYBOARD_I2C_ADDR);
    
    i2c_write_byte(0x20); // Set backlight command
    i2c_write_byte(brightness);
}

// Convert key state to key codes
pub fn decode_keys(key_state: [16]u8) [67]bool {
    var keys: [67]bool = [_]bool{false} ** 67;
    
    // Each byte represents 8 keys
    for (key_state, 0..) |byte, byte_idx| {
        var bit_idx: u3 = 0;
        while (bit_idx < 8) : (bit_idx += 1) {
            const key_idx = byte_idx * 8 + bit_idx;
            if (key_idx < 67) {
                keys[key_idx] = (byte & (@as(u8, 1) << bit_idx)) != 0;
            }
        }
    }
    
    return keys;
}

// Driver entry point (userspace service)
pub fn keyboard_driver_main() noreturn {
    // Initialize keyboard hardware
    init_keyboard();
    
    // Create IPC endpoint for this service
    const endpoint_id = syscall.UserAPI.create_endpoint() orelse {
        syscall.UserAPI.exit();
    };
    
    var last_key_state: [16]u8 = [_]u8{0} ** 16;
    
    // Main service loop
    while (true) {
        // Poll keyboard state
        const key_state = read_key_state();
        
        // Check if any keys changed
        var changed = false;
        for (key_state, 0..) |byte, idx| {
            if (byte != last_key_state[idx]) {
                changed = true;
                break;
            }
        }
        
        // If keys changed, send notification via IPC
        if (changed) {
            // Send key event to interested processes
            last_key_state = key_state;
        }
        
        // Handle incoming commands
        if (syscall.UserAPI.receive(endpoint_id)) |msg| {
            handle_message(&msg);
        }
        
        syscall.UserAPI.yield();
    }
}

fn handle_message(msg: *const ipc.Message) void {
    const data = msg.get_data();
    if (data.len < 4) return;
    
    const cmd: KeyboardCommand = @enumFromInt(@as(u32, @intCast(data[0])) |
                                               (@as(u32, @intCast(data[1])) << 8) |
                                               (@as(u32, @intCast(data[2])) << 16) |
                                               (@as(u32, @intCast(data[3])) << 24));
    
    switch (cmd) {
        .read_keys => {
            _ = read_key_state();
        },
        .set_backlight => {
            if (data.len >= 5) {
                set_backlight(data[4]);
            }
        },
        .get_status => {
            // Return keyboard status
        },
    }
}
