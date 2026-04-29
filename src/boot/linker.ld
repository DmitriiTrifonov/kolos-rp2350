/* Linker script for RP2350 RISC-V cores (Hazard3) */

MEMORY
{
    /* RP2350 has 520KB SRAM, we'll use a portion for the kernel */
    FLASH (rx)  : ORIGIN = 0x10000000, LENGTH = 4096K  /* External flash via XIP */
    RAM (rwx)   : ORIGIN = 0x20000000, LENGTH = 512K   /* SRAM */
}

ENTRY(_start)

SECTIONS
{
    .text : {
        KEEP(*(.boot))
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > FLASH

    .data : {
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT > FLASH

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
    . = . + 64K;  /* 64KB kernel heap */
    _kernel_heap_end = .;

    /* Stack for boot/kernel */
    . = ALIGN(4096);
    _stack_bottom = .;
    . = . + 16K;  /* 16KB stack */
    _stack_top = .;

    /* User space region */
    . = ALIGN(4096);
    _user_space_start = .;

    /DISCARD/ : {
        *(.comment)
        *(.note*)
    }
}
