const std = @import("std");

/// RISC-V trap handler for interrupts and exceptions
pub const Trap = struct {
    /// Trap cause codes
    pub const Cause = enum(usize) {
        // Interrupts (bit 31 set)
        supervisor_software_interrupt = 0x8000000000000001,
        machine_software_interrupt = 0x8000000000000003,
        supervisor_timer_interrupt = 0x8000000000000005,
        machine_timer_interrupt = 0x8000000000000007,
        supervisor_external_interrupt = 0x8000000000000009,
        machine_external_interrupt = 0x800000000000000B,

        // Exceptions (bit 31 clear)
        instruction_address_misaligned = 0,
        instruction_access_fault = 1,
        illegal_instruction = 2,
        breakpoint = 3,
        load_address_misaligned = 4,
        load_access_fault = 5,
        store_address_misaligned = 6,
        store_access_fault = 7,
        ecall_from_u_mode = 8,
        ecall_from_s_mode = 9,
        ecall_from_m_mode = 11,
        instruction_page_fault = 12,
        load_page_fault = 13,
        store_page_fault = 15,

        _,
    };

    /// Saved trap context
    pub const Context = extern struct {
        // General purpose registers x1-x31 (x0 is always zero)
        ra: usize, // x1 - return address
        sp: usize, // x2 - stack pointer
        gp: usize, // x3 - global pointer
        tp: usize, // x4 - thread pointer
        t0: usize, // x5 - temporary
        t1: usize, // x6 - temporary
        t2: usize, // x7 - temporary
        s0: usize, // x8 - saved register / frame pointer
        s1: usize, // x9 - saved register
        a0: usize, // x10 - argument/return value
        a1: usize, // x11 - argument/return value
        a2: usize, // x12 - argument
        a3: usize, // x13 - argument
        a4: usize, // x14 - argument
        a5: usize, // x15 - argument
        a6: usize, // x16 - argument
        a7: usize, // x17 - argument
        s2: usize, // x18 - saved register
        s3: usize, // x19 - saved register
        s4: usize, // x20 - saved register
        s5: usize, // x21 - saved register
        s6: usize, // x22 - saved register
        s7: usize, // x23 - saved register
        s8: usize, // x24 - saved register
        s9: usize, // x25 - saved register
        s10: usize, // x26 - saved register
        s11: usize, // x27 - saved register
        t3: usize, // x28 - temporary
        t4: usize, // x29 - temporary
        t5: usize, // x30 - temporary
        t6: usize, // x31 - temporary

        // CSRs
        mepc: usize, // Machine exception program counter
        mstatus: usize, // Machine status register
    };

    /// Initialize trap handling
    pub fn init() void {
        // Set trap vector to point to our handler
        // Use direct mode (low 2 bits = 00)
        const trap_vector = @intFromPtr(&trapEntry);
        writeMtvec(trap_vector);

        // Enable machine interrupts
        const mstatus = readMstatus();
        writeMstatus(mstatus | (1 << 3)); // MIE bit
    }

    /// Trap entry point (called from assembly)
    /// This will be wrapped by assembly code that saves/restores context
    export fn trapHandler(ctx: *Context) void {
        const cause = readMcause();
        const is_interrupt = (cause & (1 << 31)) != 0;
        const code = cause & 0x7FFFFFFF;

        if (is_interrupt) {
            handleInterrupt(code, ctx);
        } else {
            handleException(code, ctx);
        }
    }

    fn handleInterrupt(code: usize, ctx: *Context) void {
        _ = ctx;
        const root = @import("root");
        const hal = root.hal;
        const scheduler = @import("scheduler.zig");
        
        switch (code) {
            7 => { // Machine timer interrupt
                // Handle timer interrupt and reset timer
                const TICK_INTERVAL_US = 10000; // 10ms timeslice
                hal.Timer.handle_interrupt(TICK_INTERVAL_US);
                
                // Trigger scheduler to switch tasks
                scheduler.yield();
            },
            11 => { // Machine external interrupt
                // Handle external hardware interrupt
                // TODO: Dispatch to appropriate device driver
            },
            else => {
                // Unknown interrupt
                @panic("Unknown interrupt");
            },
        }
    }

    fn handleException(code: usize, ctx: *Context) void {
        switch (code) {
            8 => { // ecall from U-mode
                handleSyscall(ctx);
            },
            11 => { // ecall from M-mode
                handleSyscall(ctx);
            },
            2 => { // Illegal instruction
                @panic("Illegal instruction");
            },
            else => {
                // Unknown exception
                @panic("Unknown exception");
            },
        }
    }

    fn handleSyscall(ctx: *Context) void {
        // Syscall number is in a7
        // Arguments are in a0-a6
        // Return value goes in a0
        const syscall_num = ctx.a7;
        const arg0 = ctx.a0;
        const arg1 = ctx.a1;
        const arg2 = ctx.a2;

        // Import syscall module to handle the actual syscall
        const syscall = @import("syscall.zig");

        // Dispatch to syscall handler
        const result: syscall.Result = switch (syscall_num) {
            0 => syscall.sys_yield(),
            1 => syscall.sys_send(arg0, arg1, arg2),
            2 => syscall.sys_receive(arg0, arg1),
            3 => syscall.sys_create_endpoint(),
            4 => syscall.sys_destroy_endpoint(arg0),
            5 => syscall.sys_allocate_pages(arg0),
            6 => syscall.sys_free_pages(arg0, arg1),
            7 => syscall.sys_exit(arg0),
            8 => syscall.sys_create_process(arg0, arg1),
            else => syscall.Result{ .err = 1 }, // Invalid syscall
        };

        // Store result in a0 (return value) and a1 (error code)
        ctx.a0 = switch (result) {
            .ok => |val| val,
            .err => 0,
        };
        ctx.a1 = switch (result) {
            .ok => 0,
            .err => |err| err,
        };

        // Move past the ecall instruction (4 bytes)
        ctx.mepc += 4;
    }
};

/// Assembly trap entry point
/// Saves all registers, calls trapHandler, then restores registers
export fn trapEntry() noreturn {
    // Save context and call trapHandler
    asm volatile (
        \\ # Allocate space on stack for Context (33 registers * 4 bytes = 132 bytes, rounded to 136)
        \\ addi sp, sp, -136
        \\
        \\ # Save all general purpose registers
        \\ sw ra, 0(sp)
        \\ sw sp, 4(sp)   # Save original sp (will adjust later)
        \\ sw gp, 8(sp)
        \\ sw tp, 12(sp)
        \\ sw t0, 16(sp)
        \\ sw t1, 20(sp)
        \\ sw t2, 24(sp)
        \\ sw s0, 28(sp)
        \\ sw s1, 32(sp)
        \\ sw a0, 36(sp)
        \\ sw a1, 40(sp)
        \\ sw a2, 44(sp)
        \\ sw a3, 48(sp)
        \\ sw a4, 52(sp)
        \\ sw a5, 56(sp)
        \\ sw a6, 60(sp)
        \\ sw a7, 64(sp)
        \\ sw s2, 68(sp)
        \\ sw s3, 72(sp)
        \\ sw s4, 76(sp)
        \\ sw s5, 80(sp)
        \\ sw s6, 84(sp)
        \\ sw s7, 88(sp)
        \\ sw s8, 92(sp)
        \\ sw s9, 96(sp)
        \\ sw s10, 100(sp)
        \\ sw s11, 104(sp)
        \\ sw t3, 108(sp)
        \\ sw t4, 112(sp)
        \\ sw t5, 116(sp)
        \\ sw t6, 120(sp)
        \\
        \\ # Save CSRs
        \\ csrr t0, mepc
        \\ sw t0, 124(sp)
        \\ csrr t0, mstatus
        \\ sw t0, 128(sp)
        \\
        \\ # Fix saved sp to point to original value
        \\ addi t0, sp, 136
        \\ sw t0, 4(sp)
        \\
        \\ # Call trapHandler with context pointer
        \\ mv a0, sp
        \\ call trapHandler
        \\
        \\ # Restore CSRs
        \\ lw t0, 124(sp)
        \\ csrw mepc, t0
        \\ lw t0, 128(sp)
        \\ csrw mstatus, t0
        \\
        \\ # Restore all general purpose registers
        \\ lw ra, 0(sp)
        \\ # sp will be restored last
        \\ lw gp, 8(sp)
        \\ lw tp, 12(sp)
        \\ lw t0, 16(sp)
        \\ lw t1, 20(sp)
        \\ lw t2, 24(sp)
        \\ lw s0, 28(sp)
        \\ lw s1, 32(sp)
        \\ lw a0, 36(sp)
        \\ lw a1, 40(sp)
        \\ lw a2, 44(sp)
        \\ lw a3, 48(sp)
        \\ lw a4, 52(sp)
        \\ lw a5, 56(sp)
        \\ lw a6, 60(sp)
        \\ lw a7, 64(sp)
        \\ lw s2, 68(sp)
        \\ lw s3, 72(sp)
        \\ lw s4, 76(sp)
        \\ lw s5, 80(sp)
        \\ lw s6, 84(sp)
        \\ lw s7, 88(sp)
        \\ lw s8, 92(sp)
        \\ lw s9, 96(sp)
        \\ lw s10, 100(sp)
        \\ lw s11, 104(sp)
        \\ lw t3, 108(sp)
        \\ lw t4, 112(sp)
        \\ lw t5, 116(sp)
        \\ lw t6, 120(sp)
        \\
        \\ # Restore sp and return
        \\ lw sp, 4(sp)
        \\ mret
    );
    unreachable;
}

// CSR access functions
inline fn readMtvec() usize {
    return asm volatile ("csrr %[ret], mtvec"
        : [ret] "=r" (-> usize),
    );
}

inline fn writeMtvec(value: usize) void {
    asm volatile ("csrw mtvec, %[value]"
        :
        : [value] "r" (value),
    );
}

inline fn readMstatus() usize {
    return asm volatile ("csrr %[ret], mstatus"
        : [ret] "=r" (-> usize),
    );
}

inline fn writeMstatus(value: usize) void {
    asm volatile ("csrw mstatus, %[value]"
        :
        : [value] "r" (value),
    );
}

inline fn readMcause() usize {
    return asm volatile ("csrr %[ret], mcause"
        : [ret] "=r" (-> usize),
    );
}
