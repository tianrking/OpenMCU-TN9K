OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  /* The bootloader owns the top 4 KiB while it validates and copies an app. */
  RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 40K
}

SECTIONS
{
  . = ORIGIN(RAM);

  /* PicoRV32 product-loader mode enters external IRQs at RAM + 0x10. */
  .vectors ORIGIN(RAM) : ALIGN(4)
  {
    KEEP(*(.init))
  } > RAM
  ASSERT(SIZEOF(.vectors) == 16, "OpenMCU application reset vector must reserve 0x00..0x0f")

  .irq ORIGIN(RAM) + 0x10 : ALIGN(4)
  {
    KEEP(*(.irq))
  } > RAM

  .text : ALIGN(4)
  {
    *(.text.startup .text.startup.*)
    *(.text .text.*)
  } > RAM

  .rodata : ALIGN(4)
  {
    *(.rodata .rodata.*)
  } > RAM

  /* The loader copies this complete raw image into RAM before _start runs. */
  .data : ALIGN(4)
  {
    __data_start = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    __data_end = .;
  } > RAM
  __data_load_start = ADDR(.data);
  __omcu_application_payload_end = ALIGN(4);

  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  .noinit (NOLOAD) : ALIGN(16)
  {
    *(.noinit .noinit.*)
  } > RAM

  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(__stack_top >= ., "OpenMCU application SRAM overflow")
  ASSERT(__omcu_application_payload_end <= ORIGIN(RAM) + LENGTH(RAM),
         "OpenMCU application initialized image exceeds SRAM")
}
