/*
 * PicoRV32 custom-IRQ ABI wrapper for OpenMCU.
 *
 * The core enters at 0x10 with q0 = interrupted PC and q1 = a bitmask of all
 * pending IRQs. q2/q3 are explicitly documented PicoRV32 scratch registers;
 * this wrapper uses them to preserve ra/sp before it has a safe stack frame.
 * Nested interrupts are not supported by PicoRV32 while irq_active is set.
 */

    .macro OMCU_GETQ rd, qs
    .word ((0 << 25) | (0 << 20) | (\qs << 15) | (4 << 12) | (\rd << 7) | 0x0b)
    .endm

    .macro OMCU_SETQ qd, rs
    .word ((1 << 25) | (0 << 20) | (\rs << 15) | (2 << 12) | (\qd << 7) | 0x0b)
    .endm

    .macro OMCU_RETIRQ
    .word ((2 << 25) | 0x0b)
    .endm

    .macro OMCU_MASKIRQ rd, rs
    .word ((3 << 25) | (0 << 20) | (\rs << 15) | (6 << 12) | (\rd << 7) | 0x0b)
    .endm

    .macro OMCU_WAITIRQ rd
    .word ((4 << 25) | (0 << 20) | (0 << 15) | (4 << 12) | (\rd << 7) | 0x0b)
    .endm

    .section .irq, "ax", @progbits
    .balign 4
    .globl omcu_irq_entry
    .type omcu_irq_entry, @function

omcu_irq_entry:
    .option push
    .option norvc

    // q2 <- interrupted ra, q3 <- interrupted sp. No ordinary register is
    // clobbered before these two values have a protected home.
    OMCU_SETQ 2, 1
    OMCU_SETQ 3, 2

    la ra, omcu_irq_frame
    OMCU_GETQ 2, 2
    sw sp, 0(ra)                 // x1 / ra
    OMCU_GETQ 2, 3
    sw sp, 4(ra)                 // x2 / sp
    sw gp, 8(ra)                 // x3
    sw tp, 12(ra)                // x4
    sw t0, 16(ra)                // x5
    sw t1, 20(ra)                // x6
    sw t2, 24(ra)                // x7
    sw s0, 28(ra)                // x8
    sw s1, 32(ra)                // x9
    sw a0, 36(ra)                // x10
    sw a1, 40(ra)                // x11
    sw a2, 44(ra)                // x12
    sw a3, 48(ra)                // x13
    sw a4, 52(ra)                // x14
    sw a5, 56(ra)                // x15
    sw a6, 60(ra)                // x16
    sw a7, 64(ra)                // x17
    sw s2, 68(ra)                // x18
    sw s3, 72(ra)                // x19
    sw s4, 76(ra)                // x20
    sw s5, 80(ra)                // x21
    sw s6, 84(ra)                // x22
    sw s7, 88(ra)                // x23
    sw s8, 92(ra)                // x24
    sw s9, 96(ra)                // x25
    sw s10, 100(ra)              // x26
    sw s11, 104(ra)              // x27
    sw t3, 108(ra)               // x28
    sw t4, 112(ra)               // x29
    sw t5, 116(ra)               // x30
    sw t6, 120(ra)               // x31

    // Use a dedicated IRQ stack so application stack depth and handler stack
    // depth cannot corrupt one another. The public handler receives every
    // simultaneously pending CPU IRQ bit in a0.
    la sp, omcu_irq_stack_top
    OMCU_GETQ 10, 1
    call omcu_irq_dispatch

    la ra, omcu_irq_frame
    lw gp, 8(ra)
    lw tp, 12(ra)
    lw t0, 16(ra)
    lw t1, 20(ra)
    lw t2, 24(ra)
    lw s0, 28(ra)
    lw s1, 32(ra)
    lw a0, 36(ra)
    lw a1, 40(ra)
    lw a2, 44(ra)
    lw a3, 48(ra)
    lw a4, 52(ra)
    lw a5, 56(ra)
    lw a6, 60(ra)
    lw a7, 64(ra)
    lw s2, 68(ra)
    lw s3, 72(ra)
    lw s4, 76(ra)
    lw s5, 80(ra)
    lw s6, 84(ra)
    lw s7, 88(ra)
    lw s8, 92(ra)
    lw s9, 96(ra)
    lw s10, 100(ra)
    lw s11, 104(ra)
    lw t3, 108(ra)
    lw t4, 112(ra)
    lw t5, 116(ra)
    lw t6, 120(ra)
    lw sp, 4(ra)
    lw ra, 0(ra)
    OMCU_RETIRQ

    .option pop
    .size omcu_irq_entry, . - omcu_irq_entry

    .section .text.omcu_irq_api, "ax", @progbits
    .balign 4
    .globl omcu_irq_set_mask
    .type omcu_irq_set_mask, @function
omcu_irq_set_mask:
    .option push
    .option norvc
    // a0 contains the requested CPU mask and returns the previous mask.
    OMCU_MASKIRQ 10, 10
    ret
    .option pop
    .size omcu_irq_set_mask, . - omcu_irq_set_mask

    .balign 4
    .globl omcu_irq_wait
    .type omcu_irq_wait, @function
omcu_irq_wait:
    .option push
    .option norvc
    OMCU_WAITIRQ 10
    ret
    .option pop
    .size omcu_irq_wait, . - omcu_irq_wait

    // The wrapper overwrites every saved-register word before reading it and
    // normal stack rules do not require initial contents. Keep this 640-byte
    // working area out of crt0's .bss clear loop so enabling IRQ support does
    // not impose a reset-time penalty on applications that do not use it.
    .section .noinit.omcu_irq, "aw", @nobits
    .balign 16
omcu_irq_frame:
    .space 128
    .balign 16
omcu_irq_stack:
    .space 512
omcu_irq_stack_top:
