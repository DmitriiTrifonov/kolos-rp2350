// Scheduler for Kolos microkernel
// Simple round-robin cooperative scheduler
const std = @import("std");
const trap = @import("trap.zig");

// Process context (saved registers)
pub const Context = extern struct {
    // General purpose registers (callee-saved + a few others)
    ra: usize, // x1 - return address
    sp: usize, // x2 - stack pointer
    s0: usize, // x8 - saved register / frame pointer
    s1: usize, // x9 - saved register
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

    pub fn init(entry: usize, stack: usize) Context {
        return Context{
            .ra = entry, // Return address points to entry point
            .sp = stack, // Stack pointer
            .s0 = 0,
            .s1 = 0,
            .s2 = 0,
            .s3 = 0,
            .s4 = 0,
            .s5 = 0,
            .s6 = 0,
            .s7 = 0,
            .s8 = 0,
            .s9 = 0,
            .s10 = 0,
            .s11 = 0,
        };
    }
};

pub const ProcessState = enum {
    ready,
    running,
    blocked,
    waiting_for_message,
    terminated,
};

pub const MAX_PROCESSES = 8;

// Process Control Block
pub const Process = struct {
    id: u32,
    state: ProcessState,
    context: Context,
    entry_point: usize,
    ipc_endpoint: u32,
    name: [32]u8,
    
    pub fn init(id: u32, entry: usize, stack: usize, endpoint: u32, name: []const u8) Process {
        var proc = Process{
            .id = id,
            .state = .ready,
            .context = Context.init(entry, stack),
            .entry_point = entry,
            .ipc_endpoint = endpoint,
            .name = [_]u8{0} ** 32,
        };
        
        const len = @min(name.len, 31);
        @memcpy(proc.name[0..len], name[0..len]);
        
        return proc;
    }
};

// Process table
var processes: [MAX_PROCESSES]?Process = [_]?Process{null} ** MAX_PROCESSES;
var current_process_idx: usize = 0;
var next_process_id: u32 = 1;
var allocator: ?std.mem.Allocator = null;

pub fn init(alloc: std.mem.Allocator) void {
    allocator = alloc;
}

// Create a new process
pub fn create_process(entry_point: usize, stack: usize, endpoint: u32, name: []const u8) !u32 {
    // Find free slot
    for (&processes) |*slot| {
        if (slot.* == null) {
            const proc_id = next_process_id;
            next_process_id += 1;
            
            slot.* = Process.init(proc_id, entry_point, stack, endpoint, name);
            return proc_id;
        }
    }
    
    return error.TooManyProcesses;
}

// Terminate a process
pub fn terminate_process(proc_id: u32) void {
    for (&processes) |*slot| {
        if (slot.*) |proc| {
            if (proc.id == proc_id) {
                slot.* = null;
                return;
            }
        }
    }
}

// Block current process (waiting for message)
pub fn block_current() void {
    if (processes[current_process_idx]) |*proc| {
        proc.state = .waiting_for_message;
    }
}

// Unblock a process
pub fn unblock_process(proc_id: u32) void {
    for (&processes) |*slot| {
        if (slot.*) |*proc| {
            if (proc.id == proc_id and proc.state == .waiting_for_message) {
                proc.state = .ready;
                return;
            }
        }
    }
}

// Get current process
pub fn current_process() ?*Process {
    if (processes[current_process_idx]) |*proc| {
        return proc;
    }
    return null;
}

// Yield CPU (cooperative multitasking)
pub fn yield() void {
    schedule();
}

// Main scheduling function
fn schedule() void {
    // Save current process index for context switching
    const old_idx = current_process_idx;
    
    // Mark current process as ready
    if (processes[current_process_idx]) |*proc| {
        if (proc.state == .running) {
            proc.state = .ready;
        }
    }
    
    // Find next ready process (round-robin)
    var checked: usize = 0;
    while (checked < MAX_PROCESSES) : (checked += 1) {
        current_process_idx = (current_process_idx + 1) % MAX_PROCESSES;
        
        if (processes[current_process_idx]) |*proc| {
            if (proc.state == .ready) {
                proc.state = .running;
                
                // Perform context switch if we're switching to a different process
                if (old_idx != current_process_idx) {
                    if (processes[old_idx]) |*old_proc| {
                        context_switch(&old_proc.context, &proc.context);
                    } else {
                        // First process, just load context
                        load_context(&proc.context);
                    }
                }
                return;
            }
        }
    }
    
    // No ready processes, idle
    asm volatile ("wfi"); // Wait for interrupt
}

// Start the scheduler (called from kernel main)
pub fn start() noreturn {
    // DEBUG
    const uart_base: usize = 0x10000000;
    const uart_ptr: *volatile u32 = @ptrFromInt(uart_base);
    uart_ptr.* = 'S'; // Scheduler start
    
    // Find first ready process and jump to it
    for (&processes, 0..) |*slot, idx| {
        if (slot.*) |*proc| {
            if (proc.state == .ready) {
                uart_ptr.* = 'P'; // Found process
                uart_ptr.* = '0' + @as(u8, @intCast(idx));
                current_process_idx = idx;
                proc.state = .running;
                uart_ptr.* = 'L'; // About to load context
                // Jump to first process (never returns)
                load_context(&proc.context);
            }
        }
    }
    
    uart_ptr.* = 'N'; // No process found
    
    // No processes to run, just idle forever
    while (true) {
        asm volatile ("wfi");
    }
}

// Get process count
pub fn process_count() usize {
    var count: usize = 0;
    for (processes) |slot| {
        if (slot != null) count += 1;
    }
    return count;
}

/// Context switch assembly function
/// Saves current context to 'old', loads new context from 'new'
/// void context_switch(Context* old, Context* new)
export fn context_switch(old: *Context, new: *Context) void {
    asm volatile (
        \\ # Save callee-saved registers to old context
        \\ sw ra, 0(%[old])
        \\ sw sp, 4(%[old])
        \\ sw s0, 8(%[old])
        \\ sw s1, 12(%[old])
        \\ sw s2, 16(%[old])
        \\ sw s3, 20(%[old])
        \\ sw s4, 24(%[old])
        \\ sw s5, 28(%[old])
        \\ sw s6, 32(%[old])
        \\ sw s7, 36(%[old])
        \\ sw s8, 40(%[old])
        \\ sw s9, 44(%[old])
        \\ sw s10, 48(%[old])
        \\ sw s11, 52(%[old])
        \\
        \\ # Load callee-saved registers from new context
        \\ lw ra, 0(%[new])
        \\ lw sp, 4(%[new])
        \\ lw s0, 8(%[new])
        \\ lw s1, 12(%[new])
        \\ lw s2, 16(%[new])
        \\ lw s3, 20(%[new])
        \\ lw s4, 24(%[new])
        \\ lw s5, 28(%[new])
        \\ lw s6, 32(%[new])
        \\ lw s7, 36(%[new])
        \\ lw s8, 40(%[new])
        \\ lw s9, 44(%[new])
        \\ lw s10, 48(%[new])
        \\ lw s11, 52(%[new])
        \\
        \\ # Return to new context
        \\ ret
        :
        : [old] "r" (old),
          [new] "r" (new),
    );
}

/// Switch to a specific process
pub fn switch_to_process(next_proc: *Process) void {
    if (processes[current_process_idx]) |*current_proc| {
        if (current_proc.id == next_proc.id) {
            return; // Already running this process
        }
        
        // Save current context and load new context
        context_switch(&current_proc.context, &next_proc.context);
    } else {
        // No current process, just load the new context directly
        // This happens when starting the first process
        load_context(&next_proc.context);
    }
}

/// Load a context (used for starting first process)
fn load_context(ctx: *Context) noreturn {
    asm volatile (
        \\ lw ra, 0(%[ctx])
        \\ lw sp, 4(%[ctx])
        \\ lw s0, 8(%[ctx])
        \\ lw s1, 12(%[ctx])
        \\ lw s2, 16(%[ctx])
        \\ lw s3, 20(%[ctx])
        \\ lw s4, 24(%[ctx])
        \\ lw s5, 28(%[ctx])
        \\ lw s6, 32(%[ctx])
        \\ lw s7, 36(%[ctx])
        \\ lw s8, 40(%[ctx])
        \\ lw s9, 44(%[ctx])
        \\ lw s10, 48(%[ctx])
        \\ lw s11, 52(%[ctx])
        \\ ret
        :
        : [ctx] "r" (ctx),
    );
    unreachable;
}

