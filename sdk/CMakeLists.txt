cmake_minimum_required(VERSION 3.20)

project(OpenMCU_SDK LANGUAGES C ASM)

set(OMCU_MARCH "rv32imc" CACHE STRING "RISC-V ISA for the selected OpenMCU target")
set(OMCU_MABI "ilp32" CACHE STRING "RISC-V ABI for the selected OpenMCU target")

if (NOT DEFINED OMCU_RISCV_PREFIX)
  set(OMCU_RISCV_PREFIX "riscv32-unknown-elf-" CACHE STRING
      "Prefix of the RISC-V GNU toolchain executables")
endif ()
find_program(OMCU_OBJCOPY NAMES "${OMCU_RISCV_PREFIX}objcopy" REQUIRED)

function(omcu_add_firmware target)
  add_executable(${target}
    ${CMAKE_CURRENT_SOURCE_DIR}/startup/crt0.S
    ${ARGN}
  )
  target_include_directories(${target} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_compile_options(${target} PRIVATE
    -march=${OMCU_MARCH}
    -mabi=${OMCU_MABI}
    -Os
    -ffreestanding
    -fno-common
    -ffunction-sections
    -fdata-sections
    -msmall-data-limit=0
    -Wall
    -Wextra
    -Werror
  )
  target_link_options(${target} PRIVATE
    -march=${OMCU_MARCH}
    -mabi=${OMCU_MABI}
    -nostdlib
    -Wl,--gc-sections
    -Wl,-T,${CMAKE_CURRENT_SOURCE_DIR}/linker/omcu_fpga_bringup.ld
    -Wl,-Map,${CMAKE_CURRENT_BINARY_DIR}/${target}.map
  )
  set_target_properties(${target} PROPERTIES SUFFIX ".elf")
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND "${OMCU_OBJCOPY}" -O verilog --verilog-data-width=4
            "$<TARGET_FILE:${target}>"
            "${CMAKE_CURRENT_BINARY_DIR}/${target}.hex"
    BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/${target}.hex"
    COMMENT "Converting ${target} ELF to a 32-bit OpenMCU ROM image"
    VERBATIM
  )
endfunction()

omcu_add_firmware(omcu_blink examples/blink/main.c)
omcu_add_firmware(omcu_uart_hello examples/uart_hello/main.c)
omcu_add_firmware(omcu_isa_smoke examples/isa_smoke/main.c)
omcu_add_firmware(omcu_peripheral_smoke examples/peripheral_smoke/main.c)
omcu_add_firmware(omcu_wdt_reset_smoke examples/wdt_reset_smoke/main.c)
