OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  /* Generic FPGA bring-up geometry: 8 KiB ROM + 44 KiB RAM. Product MCU mode
     uses its separate 4 KiB Boot ROM linker script. */
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
  RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 44K
}

SECTIONS
{
  . = ORIGIN(ROM);

  .vectors ORIGIN(ROM) : ALIGN(4)
  {
    KEEP(*(.init))
  } > ROM
  ASSERT(SIZEOF(.vectors) == 16, "OpenMCU reset vector must reserve 0x00..0x0f")

  .irq ORIGIN(ROM) + 0x10 : ALIGN(4)
  {
    KEEP(*(.irq))
  } > ROM

  .text : ALIGN(4)
  {
    *(.text.startup .text.startup.*)
    *(.text .text.*)
  } > ROM

  .rodata : ALIGN(4)
  {
    *(.rodata .rodata.*)
  } > ROM

  .data : ALIGN(4)
  {
    __data_start = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    __data_end = .;
  } > RAM AT > ROM
  __data_load_start = LOADADDR(.data);

  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  /* IRQ frame/stack and other explicitly no-init scratch storage. */
  .noinit (NOLOAD) : ALIGN(16)
  {
    *(.noinit .noinit.*)
  } > RAM

  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(__stack_top >= ., "OpenMCU SRAM overflow")
  ASSERT(LOADADDR(.data) + SIZEOF(.data) <= ORIGIN(ROM) + LENGTH(ROM),
         "OpenMCU boot ROM overflow")
}
