// Minimal POSIX shims for freestanding target to work around Zig 0.16 std lib bugs

pub const system = struct {
    pub fn getrandom() void {}
    pub const IOV_MAX: usize = 1024;
};
