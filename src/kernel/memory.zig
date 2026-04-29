// Memory management for Kolos microkernel
const std = @import("std");

// Linker symbols
extern const _kernel_heap_start: u8;
extern const _kernel_heap_end: u8;
extern const _user_space_start: u8;

const PAGE_SIZE = 4096;
const MAX_PAGES = 128; // Manage up to 512KB of user memory

// Simple page allocator for user space
pub const PageAllocator = struct {
    bitmap: [MAX_PAGES / 8]u8,
    base_addr: usize,
    page_count: usize,
    
    pub fn init(base: usize, total_size: usize) PageAllocator {
        return PageAllocator{
            .bitmap = [_]u8{0} ** (MAX_PAGES / 8),
            .base_addr = base,
            .page_count = @min(total_size / PAGE_SIZE, MAX_PAGES),
        };
    }
    
    pub fn alloc_page(self: *PageAllocator) ?usize {
        for (&self.bitmap, 0..) |*byte, byte_idx| {
            if (byte.* == 0xFF) continue; // All bits set, no free pages
            
            var bit_idx: u3 = 0;
            while (bit_idx < 8) : (bit_idx += 1) {
                const mask: u8 = @as(u8, 1) << bit_idx;
                if (byte.* & mask == 0) {
                    // Found a free page
                    byte.* |= mask;
                    const page_idx = byte_idx * 8 + bit_idx;
                    if (page_idx >= self.page_count) return null;
                    return self.base_addr + page_idx * PAGE_SIZE;
                }
            }
        }
        return null;
    }
    
    pub fn free_page(self: *PageAllocator, addr: usize) void {
        if (addr < self.base_addr) return;
        const offset = addr - self.base_addr;
        if (offset % PAGE_SIZE != 0) return;
        
        const page_idx = offset / PAGE_SIZE;
        if (page_idx >= self.page_count) return;
        
        const byte_idx = page_idx / 8;
        const bit_idx: u3 = @intCast(page_idx % 8);
        const mask: u8 = @as(u8, 1) << bit_idx;
        
        self.bitmap[byte_idx] &= ~mask;
    }
};

// Kernel heap allocator (simple bump allocator for now)
pub const KernelHeap = struct {
    start: usize,
    end: usize,
    current: usize,
    
    pub fn init() KernelHeap {
        const start = @intFromPtr(&_kernel_heap_start);
        const end = @intFromPtr(&_kernel_heap_end);
        
        return KernelHeap{
            .start = start,
            .end = end,
            .current = start,
        };
    }
    
    pub fn allocator(self: *KernelHeap) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }
    
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *KernelHeap = @ptrCast(@alignCast(ctx));
        
        const alignment = @intFromEnum(ptr_align);
        const aligned_current = std.mem.alignForward(usize, self.current, alignment);
        const new_current = aligned_current + len;
        
        if (new_current > self.end) {
            return null; // Out of memory
        }
        
        self.current = new_current;
        return @ptrFromInt(aligned_current);
    }
    
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false; // Bump allocator doesn't support resize
    }
    
    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // Bump allocator doesn't free individual allocations
    }
    
    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return null; // Bump allocator doesn't support remap
    }
};

pub fn available_memory() usize {
    const heap_size = @intFromPtr(&_kernel_heap_end) - @intFromPtr(&_kernel_heap_start);
    return heap_size;
}

// Global page allocator instance (initialized by kernel)
var global_page_allocator: ?PageAllocator = null;

pub fn init_page_allocator() void {
    const user_space_start = @intFromPtr(&_user_space_start);
    const ram_end: usize = 0x20000000 + 512 * 1024; // RP2350 has 520KB SRAM
    const user_space_size = ram_end - user_space_start;
    
    global_page_allocator = PageAllocator.init(user_space_start, user_space_size);
}

pub fn alloc_user_page() ?usize {
    if (global_page_allocator) |*allocator| {
        return allocator.alloc_page();
    }
    return null;
}

pub fn free_user_page(addr: usize) void {
    if (global_page_allocator) |*allocator| {
        allocator.free_page(addr);
    }
}
