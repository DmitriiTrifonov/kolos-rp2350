// System call interface for Kolos microkernel
const std = @import("std");
const scheduler = @import("scheduler.zig");
const ipc = @import("ipc.zig");
const memory = @import("memory.zig");

// System call numbers
pub const SyscallNumber = enum(u32) {
    yield = 0,
    send_message = 1,
    receive_message = 2,
    create_endpoint = 3,
    alloc_page = 4,
    free_page = 5,
    exit = 6,
    get_process_id = 7,
};

// System call result
pub const SyscallResult = struct {
    success: bool,
    value: u32,
};

// Result type for trap handler
pub const Result = union(enum) {
    ok: usize,
    err: usize,
};

pub fn init() void {
    // Setup system call handler
    // In RISC-V, we would set up the trap handler here
}

// Main syscall handler (called from trap handler)
pub fn handle_syscall(syscall_num: u32, arg1: u32, arg2: u32, arg3: u32, arg4: u32) SyscallResult {
    _ = arg2;
    _ = arg3;
    _ = arg4;
    
    const syscall = @as(SyscallNumber, @enumFromInt(syscall_num));
    
    switch (syscall) {
        .yield => {
            scheduler.yield();
            return SyscallResult{ .success = true, .value = 0 };
        },
        
        .send_message => {
            // arg1 = message pointer (would need to validate/copy from userspace)
            // In real implementation, would copy message from userspace
            return SyscallResult{ .success = true, .value = 0 };
        },
        
        .receive_message => {
            // arg1 = endpoint_id
            // arg2 = message buffer pointer
            if (ipc.receive(arg1)) |msg| {
                _ = msg;
                // In real implementation, would copy message to userspace buffer
                return SyscallResult{ .success = true, .value = 1 };
            }
            return SyscallResult{ .success = false, .value = 0 };
        },
        
        .create_endpoint => {
            if (scheduler.current_process()) |proc| {
                if (ipc.create_endpoint(proc.id)) |endpoint_id| {
                    return SyscallResult{ .success = true, .value = endpoint_id };
                } else |_| {
                    return SyscallResult{ .success = false, .value = 0 };
                }
            }
            return SyscallResult{ .success = false, .value = 0 };
        },
        
        .alloc_page => {
            if (memory.alloc_user_page()) |page_addr| {
                return SyscallResult{ .success = true, .value = @intCast(page_addr) };
            }
            return SyscallResult{ .success = false, .value = 0 };
        },
        
        .free_page => {
            memory.free_user_page(arg1);
            return SyscallResult{ .success = true, .value = 0 };
        },
        
        .exit => {
            if (scheduler.current_process()) |proc| {
                scheduler.terminate_process(proc.id);
            }
            return SyscallResult{ .success = true, .value = 0 };
        },
        
        .get_process_id => {
            if (scheduler.current_process()) |proc| {
                return SyscallResult{ .success = true, .value = proc.id };
            }
            return SyscallResult{ .success = false, .value = 0 };
        },
    }
}

// Individual syscall implementations for trap handler
pub fn sys_yield() Result {
    scheduler.yield();
    return .{ .ok = 0 };
}

pub fn sys_send(endpoint_id: usize, msg_ptr: usize, msg_len: usize) Result {
    _ = endpoint_id;
    _ = msg_ptr;
    _ = msg_len;
    // TODO: Validate userspace pointer, copy message, send via IPC
    return .{ .ok = 0 };
}

pub fn sys_receive(endpoint_id: usize, buf_ptr: usize) Result {
    _ = buf_ptr;
    if (ipc.receive(@intCast(endpoint_id))) |_| {
        // TODO: Copy message to userspace buffer
        return .{ .ok = 1 };
    }
    return .{ .err = 1 }; // No message available
}

pub fn sys_create_endpoint() Result {
    if (scheduler.current_process()) |proc| {
        if (ipc.create_endpoint(proc.id)) |endpoint_id| {
            return .{ .ok = endpoint_id };
        } else |_| {
            return .{ .err = 1 };
        }
    }
    return .{ .err = 1 };
}

pub fn sys_destroy_endpoint(endpoint_id: usize) Result {
    ipc.destroy_endpoint(@intCast(endpoint_id));
    return .{ .ok = 0 };
}

pub fn sys_allocate_pages(count: usize) Result {
    _ = count;
    if (memory.alloc_user_page()) |page_addr| {
        return .{ .ok = page_addr };
    }
    return .{ .err = 1 };
}

pub fn sys_free_pages(addr: usize, count: usize) Result {
    _ = count;
    memory.free_user_page(@intCast(addr));
    return .{ .ok = 0 };
}

pub fn sys_exit(exit_code: usize) Result {
    _ = exit_code;
    if (scheduler.current_process()) |proc| {
        scheduler.terminate_process(proc.id);
    }
    return .{ .ok = 0 };
}

pub fn sys_create_process(entry_point: usize, stack_size: usize) Result {
    _ = entry_point;
    _ = stack_size;
    // TODO: Implement process creation
    return .{ .err = 1 };
}

// Userspace syscall wrapper functions (would be in a separate library)
pub const UserAPI = struct {
    pub fn syscall(num: SyscallNumber, arg1: u32, arg2: u32, arg3: u32, arg4: u32) SyscallResult {
        // In actual RISC-V, this would use ecall instruction
        // For now, directly call handler (only for testing)
        return handle_syscall(@intFromEnum(num), arg1, arg2, arg3, arg4);
    }
    
    pub fn yield() void {
        _ = syscall(.yield, 0, 0, 0, 0);
    }
    
    pub fn send(endpoint_id: u32, msg: *const ipc.Message) bool {
        _ = msg;
        const result = syscall(.send_message, endpoint_id, 0, 0, 0);
        return result.success;
    }
    
    pub fn receive(endpoint_id: u32) ?ipc.Message {
        const result = syscall(.receive_message, endpoint_id, 0, 0, 0);
        if (result.success and result.value > 0) {
            // Would return actual message
            return null;
        }
        return null;
    }
    
    pub fn create_endpoint() ?u32 {
        const result = syscall(.create_endpoint, 0, 0, 0, 0);
        if (result.success) {
            return result.value;
        }
        return null;
    }
    
    pub fn exit() noreturn {
        _ = syscall(.exit, 0, 0, 0, 0);
        unreachable;
    }
    
    pub fn get_pid() u32 {
        const result = syscall(.get_process_id, 0, 0, 0, 0);
        return result.value;
    }
};
