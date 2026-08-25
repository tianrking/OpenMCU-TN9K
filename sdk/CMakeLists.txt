cmake_minimum_required(VERSION 3.20)

project(OpenMCU_SDK LANGUAGES C ASM)

set(OMCU_MARCH "rv32imc" CACHE STRING "RISC-V ISA for the selected OpenMCU target")
set(OMCU_MABI "ilp32" CACHE STRING "RISC-V ABI for the selected OpenMCU target")

if (NOT DEFINED OMCU_RISCV_PREFIX)
  set(OMCU_RISCV_PREFIX "riscv32-unknown-elf-" CACHE STRING
      "Prefix of the RISC-V GNU toolchain executables")
endif ()
find_program(OMCU_OBJCOPY NAMES "${OMCU_RISCV_PREFIX}objcopy" REQUIRED)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(OMCU_SDK_ROOT "${CMAKE_CURRENT_SOURCE_DIR}")
set(OMCU_IMAGE_TOOL "${CMAKE_CURRENT_SOURCE_DIR}/../tools/omcu_image.py")

function(omcu_configure_firmware target linker_script)
  target_include_directories(${target} PRIVATE ${OMCU_SDK_ROOT}/include)
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
    -Wl,-T,${linker_script}
    -Wl,-Map,${CMAKE_CURRENT_BINARY_DIR}/${target}.map
  )
  set_target_properties(${target} PROPERTIES SUFFIX ".elf")
endfunction()

# Legacy ROM-image targets remain available for RTL bring-up only. They are
# intentionally distinct from omcu_add_application(), which creates a User
# Flash image for a bitstream that has already been installed in a product.
function(omcu_add_firmware target)
  add_executable(${target}
    ${OMCU_SDK_ROOT}/startup/crt0.S
    ${OMCU_SDK_ROOT}/startup/omcu_irq.S
    ${OMCU_SDK_ROOT}/runtime/omcu_irq.c
    ${ARGN}
  )
  omcu_configure_firmware(${target} ${OMCU_SDK_ROOT}/linker/omcu_fpga_bringup.ld)
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND "${OMCU_OBJCOPY}" -O verilog --verilog-data-width=4
            "$<TARGET_FILE:${target}>"
            "${CMAKE_CURRENT_BINARY_DIR}/${target}.hex"
    BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/${target}.hex"
    COMMENT "Converting ${target} ELF to a 32-bit OpenMCU ROM image"
    VERBATIM
  )
endfunction()

function(omcu_add_bootloader target)
  add_executable(${target}
    ${OMCU_SDK_ROOT}/startup/boot_crt0.S
    ${OMCU_SDK_ROOT}/runtime/omcu_memory.c
    ${OMCU_SDK_ROOT}/bootloader/omcu_bootloader.c
    ${ARGN}
  )
  omcu_configure_firmware(${target} ${OMCU_SDK_ROOT}/linker/omcu_bootloader.ld)
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND "${OMCU_OBJCOPY}" -O verilog --verilog-data-width=4
            "$<TARGET_FILE:${target}>"
            "${CMAKE_CURRENT_BINARY_DIR}/${target}.hex"
    BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/${target}.hex"
    COMMENT "Converting ${target} ELF to the immutable OpenMCU boot ROM image"
    VERBATIM
  )
endfunction()

function(omcu_add_application target)
  add_executable(${target}
    ${OMCU_SDK_ROOT}/startup/crt0.S
    ${OMCU_SDK_ROOT}/startup/omcu_irq.S
    ${OMCU_SDK_ROOT}/runtime/omcu_irq.c
    ${ARGN}
  )
  omcu_configure_firmware(${target} ${OMCU_SDK_ROOT}/linker/omcu_application.ld)
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND "${OMCU_OBJCOPY}" -O binary
            "$<TARGET_FILE:${target}>"
            "${CMAKE_CURRENT_BINARY_DIR}/${target}.bin"
    COMMAND "${Python3_EXECUTABLE}" "${OMCU_IMAGE_TOOL}" pack
            --input "${CMAKE_CURRENT_BINARY_DIR}/${target}.bin"
            --output "${CMAKE_CURRENT_BINARY_DIR}/${target}.omcu"
    BYPRODUCTS
      "${CMAKE_CURRENT_BINARY_DIR}/${target}.bin"
      "${CMAKE_CURRENT_BINARY_DIR}/${target}.omcu"
    COMMENT "Packing ${target} as an independently programmable OpenMCU application"
    VERBATIM
  )
endfunction()

omcu_add_firmware(omcu_blink examples/blink/main.c)
omcu_add_firmware(omcu_uart_hello examples/uart_hello/main.c)
omcu_add_firmware(omcu_isa_smoke examples/isa_smoke/main.c)
omcu_add_firmware(omcu_peripheral_smoke examples/peripheral_smoke/main.c)
omcu_add_firmware(omcu_i2c_smoke examples/i2c_smoke/main.c)
omcu_add_firmware(omcu_wdt_reset_smoke examples/wdt_reset_smoke/main.c)
omcu_add_firmware(omcu_tn9k_board_demo examples/tn9k_board_demo/main.c)
omcu_add_firmware(omcu_irq_smoke examples/irq_smoke/main.c)

omcu_add_bootloader(omcu_bootloader)
omcu_add_application(omcu_mcu_blink examples/mcu_blink/main.c)
