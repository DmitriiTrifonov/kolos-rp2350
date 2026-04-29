// Main entry point for Kolos microkernel
// This file serves as the root module and re-exports all components

// Re-export all submodules
pub const boot = @import("boot/start.zig");
pub const hal = @import("hal/rp2350.zig");
pub const memory = @import("kernel/memory.zig");
pub const scheduler = @import("kernel/scheduler.zig");
pub const ipc = @import("kernel/ipc.zig");
pub const syscall = @import("kernel/syscall.zig");
pub const trap = @import("kernel/trap.zig");
pub const kernel = @import("kernel/main.zig");
pub const init = @import("init.zig");

// Export the entry point and kernel_main
comptime {
    _ = boot._start_zig; // Assembly _start calls this
    _ = kernel.kernel_main;
}
