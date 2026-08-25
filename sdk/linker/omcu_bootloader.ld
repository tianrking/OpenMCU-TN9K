OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  /* Immutable loader in the FPGA image; only customer apps change later. */
  /* Product FPGA configuration reserves 4 KiB for the immutable loader. */
  ROM (rx)        : ORIGIN = 0x00000000, LENGTH = 4K
  /* Keep loader stack/data above the 40 KiB application SRAM window. */
  LOADER_RAM (rwx): ORIGIN = 0x1000A000, LENGTH = 4K
}

SECTIONS
{
  . = ORIGIN(ROM);

  .vectors ORIGIN(ROM) : ALIGN(4)
  {
    KEEP(*(.init))
  } > ROM
  ASSERT(SIZEOF(.vectors) == 16, "OpenMCU bootloader reset vector must reserve 0x00..0x0f")

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
  } > LOADER_RAM AT > ROM
  __data_load_start = LOADADDR(.data);

  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    __bss_end = .;
  } > LOADER_RAM

  .noinit (NOLOAD) : ALIGN(16)
  {
    *(.noinit .noinit.*)
  } > LOADER_RAM

  __stack_top = ORIGIN(LOADER_RAM) + LENGTH(LOADER_RAM);
  ASSERT(__stack_top >= ., "OpenMCU bootloader scratch SRAM overflow")
  ASSERT(LOADADDR(.data) + SIZEOF(.data) <= ORIGIN(ROM) + LENGTH(ROM),
         "OpenMCU bootloader ROM overflow")
}
