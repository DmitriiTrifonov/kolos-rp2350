/* Linker script for QEMU virt machine (RISC-V 32-bit) */

MEMORY
{
    /* QEMU virt machine RAM starts at 0x80000000 */
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

ENTRY(_start)

SECTIONS
{
    . = 0x80000000;

    .text : {
        KEEP(*(.boot))
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > RAM

    .data : {
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM

    _sidata = LOADADDR(.data);

    .bss : {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /* Kernel heap comes after BSS */
    . = ALIGN(4096);
    _kernel_heap_start = .;
    . = . + 1M;  /* 1MB kernel heap for QEMU */
    _kernel_heap_end = .;

    /* Stack for boot/kernel */
    . = ALIGN(4096);
    _stack_bottom = .;
    . = . + 64K;  /* 64KB stack */
    _stack_top = .;

    /* User space region */
    . = ALIGN(4096);
    _user_space_start = .;

    /DISCARD/ : {
        *(.comment)
        *(.note*)
    }
}
