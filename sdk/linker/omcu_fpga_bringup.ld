OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
  RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 32K
}

SECTIONS
{
  . = ORIGIN(ROM);

  .text : ALIGN(4)
  {
    KEEP(*(.init))
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

  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(__stack_top >= ., "OpenMCU SRAM overflow")
  ASSERT(LOADADDR(.data) + SIZEOF(.data) <= ORIGIN(ROM) + LENGTH(ROM),
         "OpenMCU boot ROM overflow")
}
