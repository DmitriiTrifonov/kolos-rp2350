// ST7789 Display driver for PicoCalc (320x320 IPS via SPI)
// Userspace driver service for microkernel architecture
const std = @import("std");
const syscall = @import("../kernel/syscall.zig");
const ipc = @import("../kernel/ipc.zig");

// Display dimensions
pub const SCREEN_WIDTH = 320;
pub const SCREEN_HEIGHT = 320;

// ST7789 Commands
const ST7789_NOP: u8 = 0x00;
const ST7789_SWRESET: u8 = 0x01;
const ST7789_SLPOUT: u8 = 0x11;
const ST7789_NORON: u8 = 0x13;
const ST7789_INVOFF: u8 = 0x20;
const ST7789_INVON: u8 = 0x21;
const ST7789_DISPOFF: u8 = 0x28;
const ST7789_DISPON: u8 = 0x29;
const ST7789_CASET: u8 = 0x2A;
const ST7789_RASET: u8 = 0x2B;
const ST7789_RAMWR: u8 = 0x2C;
const ST7789_MADCTL: u8 = 0x36;
const ST7789_COLMOD: u8 = 0x3A;

// GPIO pins for display control (typical PicoCalc configuration)
const PIN_DC: u8 = 8;   // Data/Command pin
const PIN_CS: u8 = 9;   // Chip Select pin
const PIN_RST: u8 = 12; // Reset pin
const PIN_BL: u8 = 13;  // Backlight pin

// SPI base address
const SPI_BASE: usize = 0x40040000; // SPI0
const SPI_SSPDR: usize = 0x08;
const SPI_SSPSR: usize = 0x0C;

// GPIO SIO base
const SIO_BASE: usize = 0xd0000000;

// Display message types
pub const DisplayCommand = enum(u32) {
    init,
    clear,
    set_pixel,
    draw_rect,
    draw_char,
    update,
    set_backlight,
};

// Hardware access helpers
fn gpio_put(pin: u8, value: bool) void {
    const mask: u32 = @as(u32, 1) << @intCast(pin);
    if (value) {
        const ptr: *volatile u32 = @ptrFromInt(SIO_BASE + 0x014);
        ptr.* = mask;
    } else {
        const ptr: *volatile u32 = @ptrFromInt(SIO_BASE + 0x018);
        ptr.* = mask;
    }
}

fn spi_write(byte: u8) void {
    const sspdr: *volatile u32 = @ptrFromInt(SPI_BASE + SPI_SSPDR);
    const sspsr: *volatile u32 = @ptrFromInt(SPI_BASE + SPI_SSPSR);
    
    // Wait for TX FIFO not full
    while ((sspsr.* & 0x02) == 0) {}
    sspdr.* = byte;
    
    // Wait for transmission complete
    while ((sspsr.* & 0x10) != 0) {}
}

fn delay_ms(ms: u32) void {
    const cycles = ms * 150000; // 150 MHz = 150,000 cycles per ms
    var i: u32 = 0;
    while (i < cycles) : (i += 1) {
        asm volatile ("nop");
    }
}

// Display driver functions
fn write_command(cmd: u8) void {
    gpio_put(PIN_DC, false); // Command mode
    gpio_put(PIN_CS, false); // Select display
    spi_write(cmd);
    gpio_put(PIN_CS, true); // Deselect
}

fn write_data(data: u8) void {
    gpio_put(PIN_DC, true); // Data mode
    gpio_put(PIN_CS, false); // Select display
    spi_write(data);
    gpio_put(PIN_CS, true); // Deselect
}

fn write_data_bytes(data: []const u8) void {
    gpio_put(PIN_DC, true); // Data mode
    gpio_put(PIN_CS, false); // Select display
    for (data) |byte| {
        spi_write(byte);
    }
    gpio_put(PIN_CS, true); // Deselect
}

fn set_address_window(x0: u16, y0: u16, x1: u16, y1: u16) void {
    // Column address set
    write_command(ST7789_CASET);
    write_data(@intCast(x0 >> 8));
    write_data(@intCast(x0 & 0xFF));
    write_data(@intCast(x1 >> 8));
    write_data(@intCast(x1 & 0xFF));
    
    // Row address set
    write_command(ST7789_RASET);
    write_data(@intCast(y0 >> 8));
    write_data(@intCast(y0 & 0xFF));
    write_data(@intCast(y1 >> 8));
    write_data(@intCast(y1 & 0xFF));
    
    // Write to RAM
    write_command(ST7789_RAMWR);
}

pub fn init_display() void {
    // Reset display
    gpio_put(PIN_RST, false);
    delay_ms(10);
    gpio_put(PIN_RST, true);
    delay_ms(10);
    
    // Software reset
    write_command(ST7789_SWRESET);
    delay_ms(150);
    
    // Sleep out
    write_command(ST7789_SLPOUT);
    delay_ms(10);
    
    // Color mode: 16-bit (RGB565)
    write_command(ST7789_COLMOD);
    write_data(0x55); // 16-bit color
    
    // Memory data access control
    write_command(ST7789_MADCTL);
    write_data(0x00); // Normal orientation
    
    // Normal display mode on
    write_command(ST7789_NORON);
    delay_ms(10);
    
    // Display on
    write_command(ST7789_DISPON);
    delay_ms(10);
    
    // Turn on backlight
    gpio_put(PIN_BL, true);
}

pub fn clear_screen(color: u16) void {
    set_address_window(0, 0, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1);
    
    const color_hi: u8 = @intCast(color >> 8);
    const color_lo: u8 = @intCast(color & 0xFF);
    
    gpio_put(PIN_DC, true);
    gpio_put(PIN_CS, false);
    
    var i: u32 = 0;
    while (i < SCREEN_WIDTH * SCREEN_HEIGHT) : (i += 1) {
        spi_write(color_hi);
        spi_write(color_lo);
    }
    
    gpio_put(PIN_CS, true);
}

pub fn draw_pixel(x: u16, y: u16, color: u16) void {
    if (x >= SCREEN_WIDTH or y >= SCREEN_HEIGHT) return;
    
    set_address_window(x, y, x, y);
    write_data(@intCast(color >> 8));
    write_data(@intCast(color & 0xFF));
}

pub fn draw_rect(x: u16, y: u16, w: u16, h: u16, color: u16) void {
    set_address_window(x, y, x + w - 1, y + h - 1);
    
    const color_hi: u8 = @intCast(color >> 8);
    const color_lo: u8 = @intCast(color & 0xFF);
    
    gpio_put(PIN_DC, true);
    gpio_put(PIN_CS, false);
    
    var i: u32 = 0;
    while (i < @as(u32, w) * @as(u32, h)) : (i += 1) {
        spi_write(color_hi);
        spi_write(color_lo);
    }
    
    gpio_put(PIN_CS, true);
}

// RGB565 color constants
pub const Color = struct {
    pub const BLACK: u16 = 0x0000;
    pub const WHITE: u16 = 0xFFFF;
    pub const RED: u16 = 0xF800;
    pub const GREEN: u16 = 0x07E0;
    pub const BLUE: u16 = 0x001F;
    pub const CYAN: u16 = 0x07FF;
    pub const MAGENTA: u16 = 0xF81F;
    pub const YELLOW: u16 = 0xFFE0;
    pub const GRAY: u16 = 0x8410;
};

// Driver entry point (userspace service)
pub fn display_driver_main() noreturn {
    // Initialize display hardware
    init_display();
    clear_screen(Color.BLACK);
    
    // Create IPC endpoint for this service
    const endpoint_id = syscall.UserAPI.create_endpoint() orelse {
        syscall.UserAPI.exit();
    };
    
    // Main service loop
    while (true) {
        // Wait for display commands
        if (syscall.UserAPI.receive(endpoint_id)) |msg| {
            handle_message(&msg);
        }
        
        syscall.UserAPI.yield();
    }
}

fn handle_message(msg: *const ipc.Message) void {
    const data = msg.get_data();
    if (data.len < 4) return;
    
    const cmd: DisplayCommand = @enumFromInt(@as(u32, @intCast(data[0])) |
                                             (@as(u32, @intCast(data[1])) << 8) |
                                             (@as(u32, @intCast(data[2])) << 16) |
                                             (@as(u32, @intCast(data[3])) << 24));
    
    switch (cmd) {
        .init => init_display(),
        .clear => {
            if (data.len >= 6) {
                const color = @as(u16, @intCast(data[4])) | (@as(u16, @intCast(data[5])) << 8);
                clear_screen(color);
            }
        },
        .set_pixel => {
            if (data.len >= 10) {
                const x = @as(u16, @intCast(data[4])) | (@as(u16, @intCast(data[5])) << 8);
                const y = @as(u16, @intCast(data[6])) | (@as(u16, @intCast(data[7])) << 8);
                const color = @as(u16, @intCast(data[8])) | (@as(u16, @intCast(data[9])) << 8);
                draw_pixel(x, y, color);
            }
        },
        .draw_rect => {
            if (data.len >= 12) {
                const x = @as(u16, @intCast(data[4])) | (@as(u16, @intCast(data[5])) << 8);
                const y = @as(u16, @intCast(data[6])) | (@as(u16, @intCast(data[7])) << 8);
                const w = @as(u16, @intCast(data[8])) | (@as(u16, @intCast(data[9])) << 8);
                const h = @as(u16, @intCast(data[10])) | (@as(u16, @intCast(data[11])) << 8);
                const color = @as(u16, @intCast(data[12])) | (@as(u16, @intCast(data[13])) << 8);
                draw_rect(x, y, w, h, color);
            }
        },
        .set_backlight => {
            if (data.len >= 5) {
                const on = data[4] != 0;
                gpio_put(PIN_BL, on);
            }
        },
        else => {},
    }
}
