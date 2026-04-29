// Custom memory utilities for freestanding kernel (no std dependency)

/// Align forward to the specified alignment
pub inline fn alignForward(addr: usize, alignment: usize) usize {
    return (addr + alignment - 1) & ~(alignment - 1);
}

/// Alignment type for allocator
pub const Alignment = enum(u8) {
    @"1" = 0,
    @"2" = 1,
    @"4" = 2,
    @"8" = 3,
    @"16" = 4,
    @"32" = 5,
    @"64" = 6,
    @"128" = 7,
    @"256" = 8,
    
    pub fn toBytes(self: Alignment) usize {
        return @as(usize, 1) << @intFromEnum(self);
    }
};

/// Simple allocator interface (no std dependency)
pub const Allocator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,
    
    pub const VTable = struct {
        alloc: *const fn (ctx: *anyopaque, len: usize, alignment: Alignment) ?[*]u8,
        free: *const fn (ctx: *anyopaque, ptr: [*]u8, len: usize, alignment: Alignment) void,
    };
    
    pub fn alloc(self: Allocator, len: usize, alignment: Alignment) ?[*]u8 {
        return self.vtable.alloc(self.ptr, len, alignment);
    }
    
    pub fn free(self: Allocator, ptr: [*]u8, len: usize, alignment: Alignment) void {
        self.vtable.free(self.ptr, ptr, len, alignment);
    }
};
