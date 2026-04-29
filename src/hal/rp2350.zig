// Hardware Abstraction Layer for RP2350 (RISC-V cores) and QEMU virt machine
const std = @import("std");
const build_options = @import("build_options");
const is_qemu = build_options.is_qemu;

// RP2350 peripheral base addresses
pub const RESETS_BASE: usize = 0x40020000;
pub const IO_BANK0_BASE: usize = 0x40028000;
pub const PADS_BANK0_BASE: usize = 0x4002c000;
pub const SIO_BASE: usize = 0xd0000000;
pub const UART0_BASE: usize = 0x40070000;
pub const UART1_BASE: usize = 0x40078000;
pub const SPI0_BASE: usize = 0x40040000;
pub const SPI1_BASE: usize = 0x40044000;
pub const I2C0_BASE: usize = 0x40060000;
pub const I2C1_BASE: usize = 0x40064000;
pub const CLOCKS_BASE: usize = 0x40010000;
pub const XOSC_BASE: usize = 0x40048000;
pub const PLL_SYS_BASE: usize = 0x40050000;
pub const PLL_USB_BASE: usize = 0x40058000;

// Volatile register access
fn read_reg(addr: usize) u32 {
    const ptr: *volatile u32 = @ptrFromInt(addr);
    return ptr.*;
}

fn write_reg(addr: usize, value: u32) void {
    const ptr: *volatile u32 = @ptrFromInt(addr);
    ptr.* = value;
}

fn set_bits(addr: usize, bits: u32) void {
    write_reg(addr, read_reg(addr) | bits);
}

fn clear_bits(addr: usize, bits: u32) void {
    write_reg(addr, read_reg(addr) & ~bits);
}

// Clock initialization
pub fn init_clocks() void {
    // Enable XOSC (12 MHz crystal)
    write_reg(XOSC_BASE + 0x00, 0xAA0); // CTRL
    write_reg(XOSC_BASE + 0x0C, 0x2F); // STARTUP delay
    set_bits(XOSC_BASE + 0x00, 0xFAB000); // Enable XOSC
    
    // Wait for XOSC to stabilize
    while ((read_reg(XOSC_BASE + 0x04) & 0x80000000) == 0) {}
    
    // Configure PLL_SYS for 150 MHz
    // VCO = 12 MHz * 125 = 1500 MHz
    // Divide by 10 to get 150 MHz
    const pll_sys_fbdiv: u32 = 125;
    const pll_sys_postdiv1: u32 = 5;
    const pll_sys_postdiv2: u32 = 2;
    
    write_reg(PLL_SYS_BASE + 0x08, pll_sys_fbdiv); // FBDIV
    write_reg(PLL_SYS_BASE + 0x00, 0x1); // Power on PLL
    
    // Wait for PLL lock
    while ((read_reg(PLL_SYS_BASE + 0x04) & 0x1) == 0) {}
    
    write_reg(PLL_SYS_BASE + 0x0C, (pll_sys_postdiv1 << 16) | pll_sys_postdiv2);
    write_reg(PLL_SYS_BASE + 0x00, 0x9); // Turn on post dividers
}

// Reset controller
pub fn unreset_block(bit: u5) void {
    const offset: usize = 0x3000; // RESET_DONE offset
    clear_bits(RESETS_BASE, @as(u32, 1) << bit);
    while ((read_reg(RESETS_BASE + offset) & (@as(u32, 1) << bit)) == 0) {}
}

// GPIO initialization
pub fn gpio_init(pin: u8) void {
    const gpio_ctrl_offset = IO_BANK0_BASE + 0x04 + (@as(usize, pin) * 8);
    const pad_ctrl_offset = PADS_BANK0_BASE + 0x04 + @as(usize, pin) * 4;
    
    // Set function to SIO (5)
    write_reg(gpio_ctrl_offset, 5);
    
    // Enable output, input, set drive strength
    write_reg(pad_ctrl_offset, 0x56); // Output disable off, input enable on
}

pub fn gpio_set_function(pin: u8, function: u8) void {
    const gpio_ctrl_offset = IO_BANK0_BASE + 0x04 + (@as(usize, pin) * 8);
    write_reg(gpio_ctrl_offset, function);
}

// GPIO SIO (Single-cycle IO) operations
pub fn gpio_set_output(pin: u8) void {
    gpio_init(pin);
    const mask: u32 = @as(u32, 1) << @intCast(pin);
    write_reg(SIO_BASE + 0x024, mask); // GPIO_OE_SET
}

pub fn gpio_set_input(pin: u8) void {
    gpio_init(pin);
    const mask: u32 = @as(u32, 1) << @intCast(pin);
    write_reg(SIO_BASE + 0x028, mask); // GPIO_OE_CLR
}

pub fn gpio_put(pin: u8, value: bool) void {
    const mask: u32 = @as(u32, 1) << @intCast(pin);
    if (value) {
        write_reg(SIO_BASE + 0x014, mask); // GPIO_OUT_SET
    } else {
        write_reg(SIO_BASE + 0x018, mask); // GPIO_OUT_CLR
    }
}

pub fn gpio_get(pin: u8) bool {
    const mask: u32 = @as(u32, 1) << @intCast(pin);
    return (read_reg(SIO_BASE + 0x004) & mask) != 0; // GPIO_IN
}

pub fn gpio_toggle(pin: u8) void {
    const mask: u32 = @as(u32, 1) << @intCast(pin);
    write_reg(SIO_BASE + 0x01C, mask); // GPIO_OUT_XOR
}

// UART register offsets
const UART_DR: usize = 0x00;
const UART_FR: usize = 0x18;
const UART_IBRD: usize = 0x24;
const UART_FBRD: usize = 0x28;
const UART_LCR_H: usize = 0x2C;
const UART_CR: usize = 0x30;

pub const UART = struct {
    base: usize,
    is_qemu_uart: bool,
    
    // QEMU NS16550A UART initialization
    pub fn init_qemu() UART {
        const QEMU_UART_BASE: usize = 0x10000000;
        // NS16550A is already initialized by QEMU, just return
        return UART{ 
            .base = QEMU_UART_BASE,
            .is_qemu_uart = true,
        };
    }
    
    pub fn init(uart_num: u8, baud_rate: u32) UART {
        const base = if (uart_num == 0) UART0_BASE else UART1_BASE;
        
        // Unreset UART
        unreset_block(@intCast(22 + uart_num)); // UART0 = bit 22, UART1 = bit 23
        
        // Configure UART
        // Assuming 150 MHz clock, calculate baud divisor
        const clock_freq: u32 = 150_000_000;
        const baud_div = (clock_freq * 4) / baud_rate;
        const ibrd = baud_div >> 6;
        const fbrd = baud_div & 0x3F;
        
        write_reg(base + UART_IBRD, ibrd);
        write_reg(base + UART_FBRD, fbrd);
        
        // 8N1, FIFO enabled
        write_reg(base + UART_LCR_H, (0x3 << 5) | (1 << 4)); // 8 bits, FIFO on
        
        // Enable UART, TX, RX
        write_reg(base + UART_CR, (1 << 0) | (1 << 8) | (1 << 9));
        
        // Configure GPIO pins
        if (uart_num == 0) {
            gpio_set_function(0, 2); // TX
            gpio_set_function(1, 2); // RX
        } else {
            gpio_set_function(8, 2); // TX
            gpio_set_function(9, 2); // RX
        }
        
        return UART{ 
            .base = base,
            .is_qemu_uart = false,
        };
    }
    
    pub fn putc(self: *const UART, c: u8) void {
        if (self.is_qemu_uart) {
            // NS16550A - just write to data register
            write_reg(self.base, c);
        } else {
            // PL011 UART (RP2350)
            // Wait for TX FIFO not full
            while ((read_reg(self.base + UART_FR) & (1 << 5)) != 0) {}
            write_reg(self.base + UART_DR, c);
        }
    }
    
    pub fn getc(self: *const UART) ?u8 {
        if (self.is_qemu_uart) {
            // NS16550A LSR bit 0 is data ready
            const lsr = read_reg(self.base + 5);
            if ((lsr & 0x01) != 0) {
                return @intCast(read_reg(self.base) & 0xFF);
            }
            return null;
        } else {
            // PL011 UART (RP2350)
            // Check if RX FIFO is empty
            if ((read_reg(self.base + UART_FR) & (1 << 4)) != 0) {
                return null;
            }
            return @intCast(read_reg(self.base + UART_DR) & 0xFF);
        }
    }
    
    pub fn puts(self: *const UART, str: []const u8) void {
        for (str) |c| {
            self.putc(c);
        }
    }
};

// Global UART instance
var uart0: ?UART = null;

pub fn init() void {
    if (is_qemu) {
        // QEMU virt machine - simple UART init
        uart0 = UART.init_qemu();
    } else {
        // RP2350 - initialize clocks first
        init_clocks();
        uart0 = UART.init(0, 115200);
    }
}

pub fn debug_uart() ?*const UART {
    if (uart0) |*uart| {
        return uart;
    }
    return null;
}

// SPI register offsets
const SPI_SSPCR0: usize = 0x00;
const SPI_SSPCR1: usize = 0x04;
const SPI_SSPDR: usize = 0x08;
const SPI_SSPSR: usize = 0x0C;
const SPI_SSPCPSR: usize = 0x10;

pub const SPI = struct {
    base: usize,
    
    pub fn init(spi_num: u8, baudrate: u32) SPI {
        const base = if (spi_num == 0) SPI0_BASE else SPI1_BASE;
        
        // Unreset SPI
        unreset_block(16 + spi_num); // SPI0 = bit 16, SPI1 = bit 17
        
        // Calculate prescaler (must be even, 2-254)
        const clock_freq: u32 = 150_000_000;
        var prescale: u32 = 2;
        while (prescale <= 254) : (prescale += 2) {
            if (clock_freq / prescale <= baudrate) break;
        }
        
        // Disable SPI before configuration
        write_reg(base + SPI_SSPCR1, 0);
        
        // Set clock prescaler
        write_reg(base + SPI_SSPCPSR, prescale);
        
        // Configure SPI: 8-bit, SPI mode 0, Motorola format
        write_reg(base + SPI_SSPCR0, 0x07); // 8-bit data
        
        // Enable SPI
        write_reg(base + SPI_SSPCR1, 0x02); // Enable SPI, master mode
        
        // Configure GPIO pins for SPI
        if (spi_num == 0) {
            gpio_set_function(16, 1); // RX (MISO)
            gpio_set_function(17, 1); // CSn
            gpio_set_function(18, 1); // SCK
            gpio_set_function(19, 1); // TX (MOSI)
        } else {
            gpio_set_function(12, 1); // RX
            gpio_set_function(13, 1); // CSn
            gpio_set_function(14, 1); // SCK
            gpio_set_function(15, 1); // TX
        }
        
        return SPI{ .base = base };
    }
    
    pub fn write_byte(self: *const SPI, byte: u8) void {
        // Wait for TX FIFO not full
        while ((read_reg(self.base + SPI_SSPSR) & 0x02) == 0) {}
        write_reg(self.base + SPI_SSPDR, byte);
        
        // Wait for transmission complete
        while ((read_reg(self.base + SPI_SSPSR) & 0x10) != 0) {}
    }
    
    pub fn write_bytes(self: *const SPI, data: []const u8) void {
        for (data) |byte| {
            self.write_byte(byte);
        }
    }
    
    pub fn read_byte(self: *const SPI) u8 {
        // Dummy write to generate clock
        self.write_byte(0xFF);
        
        // Wait for RX FIFO not empty
        while ((read_reg(self.base + SPI_SSPSR) & 0x04) == 0) {}
        return @intCast(read_reg(self.base + SPI_SSPDR) & 0xFF);
    }
};

// ========================================
// Timer Support (RISC-V Machine Timer)
// ========================================

/// Timer for preemptive scheduling
/// Uses RISC-V mtime and mtimecmp registers
pub const Timer = struct {
    // RP2350 timer base (memory-mapped mtime for RISC-V)
    pub const RP2350_TIMER_BASE: usize = 0x40054000;
    pub const RP2350_MTIME_OFFSET: usize = 0x00;
    pub const RP2350_MTIMECMP_OFFSET: usize = 0x08;
    
    // QEMU virt machine CLINT
    pub const QEMU_CLINT_BASE: usize = 0x02000000;
    pub const QEMU_MTIME_OFFSET: usize = 0xbff8;
    pub const QEMU_MTIMECMP_OFFSET: usize = 0x4000;
    
    /// Read current time (64-bit)
    pub fn read_time() u64 {
        const timer_base = if (is_qemu) QEMU_CLINT_BASE else RP2350_TIMER_BASE;
        const mtime_offset = if (is_qemu) QEMU_MTIME_OFFSET else RP2350_MTIME_OFFSET;
        
        const mtime_lo = read_reg(timer_base + mtime_offset);
        const mtime_hi = read_reg(timer_base + mtime_offset + 4);
        return (@as(u64, mtime_hi) << 32) | @as(u64, mtime_lo);
    }
    
    /// Set timer compare value (triggers interrupt when mtime >= mtimecmp)
    pub fn set_compare(value: u64) void {
        const timer_base = if (is_qemu) QEMU_CLINT_BASE else RP2350_TIMER_BASE;
        const mtimecmp_offset = if (is_qemu) QEMU_MTIMECMP_OFFSET else RP2350_MTIMECMP_OFFSET;
        
        // Write high word to max first to avoid spurious interrupt
        write_reg(timer_base + mtimecmp_offset + 4, 0xFFFFFFFF);
        write_reg(timer_base + mtimecmp_offset, @truncate(value));
        write_reg(timer_base + mtimecmp_offset + 4, @truncate(value >> 32));
    }
    
    /// Initialize timer with given tick interval (in microseconds)
    /// Both RP2350 and QEMU timers run at different frequencies
    /// RP2350: 1 MHz (1 tick = 1 us)
    /// QEMU: 10 MHz (10 ticks = 1 us)
    pub fn init(interval_us: u32) void {
        const ticks = if (is_qemu) interval_us * 10 else interval_us;
        const current = read_time();
        set_compare(current + ticks);
        enable_interrupt();
    }
    
    /// Enable machine timer interrupt
    pub fn enable_interrupt() void {
        // Set MIE.MTIE bit (bit 7) in mie register
        asm volatile (
            \\ csrr t0, mie
            \\ ori t0, t0, 0x80
            \\ csrw mie, t0
        );
    }
    
    /// Disable machine timer interrupt
    pub fn disable_interrupt() void {
        // Clear MIE.MTIE bit (bit 7) in mie register
        asm volatile (
            \\ csrr t0, mie
            \\ andi t0, t0, ~0x80
            \\ csrw mie, t0
        );
    }
    
    /// Handle timer interrupt (called from trap handler)
    /// Sets next compare value and returns
    pub fn handle_interrupt(interval_us: u32) void {
        const ticks = if (is_qemu) interval_us * 10 else interval_us;
        const current = read_time();
        set_compare(current + ticks);
    }
};

/// Delay functions
pub const Delay = struct {
    pub fn delay_us(us: u32) void {
        const start = Timer.read_time();
        while (Timer.read_time() - start < us) {}
    }
    
    pub fn delay_ms(ms: u32) void {
        delay_us(ms * 1000);
    }
};

