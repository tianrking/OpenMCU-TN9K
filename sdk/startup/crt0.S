    .section .init, "ax", @progbits
    .globl _start
    .type _start, @function

_start:
    // PicoRV32 enters external interrupts at 0x10. Keep exactly four
    // uncompressed words here, then place the executable IRQ wrapper at the
    // fixed vector before normal reset/startup code.
    .option push
    .option norvc
    j omcu_reset
    nop
    nop
    nop
    .option pop

    .size _start, . - _start

    .section .text.startup, "ax", @progbits
    .globl omcu_reset
    .type omcu_reset, @function

omcu_reset:
    la sp, __stack_top

    la a0, __data_load_start
    la a1, __data_start
    la a2, __data_end
1:
    bgeu a1, a2, 2f
    lw t0, 0(a0)
    sw t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    j 1b

2:
    la a1, __bss_start
    la a2, __bss_end
3:
    bgeu a1, a2, 4f
    sw zero, 0(a1)
    addi a1, a1, 4
    j 3b

4:
    call main
5:
    j 5b

    .size omcu_reset, . - omcu_reset
