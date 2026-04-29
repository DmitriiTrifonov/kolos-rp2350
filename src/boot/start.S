.section .boot, "ax"
.global _start
.type _start, @function

_start:
    # Setup global pointer (optional, for relaxation)
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    
    # Setup stack pointer
    la sp, _stack_top
    
    # Clear BSS and copy data (done in Zig code)
    
    # Jump to Zig entry point
    call _start_zig
    
    # Should never return, but loop just in case
1:
    j 1b

.size _start, . - _start
