include_guard(GLOBAL)

# Public CMake entry point for both in-tree examples and customer projects.
# Derive the SDK location from this file so applications may live anywhere on
# disk and only need to include this module from a cloned or released SDK.
get_filename_component(OMCU_SDK_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
get_filename_component(OMCU_REPOSITORY_ROOT "${OMCU_SDK_ROOT}/.." ABSOLUTE)

set(OMCU_MARCH "rv32im" CACHE STRING
    "RISC-V ISA for the selected OpenMCU target")
set(OMCU_MABI "ilp32" CACHE STRING
    "RISC-V ABI for the selected OpenMCU target")

if (NOT DEFINED OMCU_RISCV_PREFIX)
  set(OMCU_RISCV_PREFIX "riscv32-unknown-elf-" CACHE STRING
      "Prefix of the RISC-V GNU toolchain executables")
endif ()

find_program(OMCU_OBJCOPY NAMES "${OMCU_RISCV_PREFIX}objcopy" REQUIRED)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(OMCU_IMAGE_TOOL "${OMCU_REPOSITORY_ROOT}/tools/omcu_image.py")
set(OMCU_BOOTLOADER_FIXTURE_TOOL
    "${OMCU_REPOSITORY_ROOT}/tools/omcu_bootloader_fixture.py")
set(OMCU_BOOTLOADER_FIXTURE
    "${OMCU_REPOSITORY_ROOT}/rtl/platform/tangnano9k/firmware/bootloader.hex")

foreach (_omcu_required_file
    "${OMCU_SDK_ROOT}/startup/crt0.S"
    "${OMCU_SDK_ROOT}/linker/omcu_application.ld"
    "${OMCU_IMAGE_TOOL}")
  if (NOT EXISTS "${_omcu_required_file}")
    message(FATAL_ERROR
      "Incomplete OpenMCU SDK at ${OMCU_SDK_ROOT}: missing ${_omcu_required_file}")
  endif ()
endforeach ()

# Optional device drivers are an ordinary static library. Applications retain
# ownership of all I/O electrical choices, target addresses and timeouts.
if (NOT TARGET omcu_device_drivers)
  add_library(omcu_device_drivers STATIC
    "${OMCU_SDK_ROOT}/drivers/omcu_bus.c"
    "${OMCU_SDK_ROOT}/drivers/omcu_devices.c"
  )
  add_library(OpenMCU::device_drivers ALIAS omcu_device_drivers)
  target_include_directories(omcu_device_drivers PUBLIC
    "${OMCU_SDK_ROOT}/include")
  target_compile_options(omcu_device_drivers PRIVATE
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
endif ()

function(omcu_configure_firmware target linker_script)
  target_include_directories(${target} PRIVATE "${OMCU_SDK_ROOT}/include")
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
# deliberately separate from independently programmable product applications.
function(omcu_add_firmware target)
  add_executable(${target}
    "${OMCU_SDK_ROOT}/startup/crt0.S"
    "${OMCU_SDK_ROOT}/startup/omcu_irq.S"
    "${OMCU_SDK_ROOT}/runtime/omcu_irq.c"
    ${ARGN}
  )
  omcu_configure_firmware(
    ${target} "${OMCU_SDK_ROOT}/linker/omcu_fpga_bringup.ld")
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
    "${OMCU_SDK_ROOT}/startup/boot_crt0.S"
    "${OMCU_SDK_ROOT}/runtime/omcu_memory.c"
    "${OMCU_SDK_ROOT}/bootloader/omcu_bootloader.c"
    ${ARGN}
  )
  omcu_configure_firmware(
    ${target} "${OMCU_SDK_ROOT}/linker/omcu_bootloader.ld")
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND "${OMCU_OBJCOPY}" -O verilog --verilog-data-width=4
            "$<TARGET_FILE:${target}>"
            "${CMAKE_CURRENT_BINARY_DIR}/${target}.hex"
    BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/${target}.hex"
    COMMENT "Converting ${target} ELF to the immutable OpenMCU boot ROM image"
    VERBATIM
  )
endfunction()

# Public customer-application constructor. It owns the startup code, product
# SRAM linker contract and .omcu image packing, so application projects only
# list their own sources and optional SDK driver libraries.
function(omcu_add_application target)
  add_executable(${target}
    "${OMCU_SDK_ROOT}/startup/crt0.S"
    "${OMCU_SDK_ROOT}/startup/omcu_irq.S"
    "${OMCU_SDK_ROOT}/runtime/omcu_irq.c"
    ${ARGN}
  )
  omcu_configure_firmware(
    ${target} "${OMCU_SDK_ROOT}/linker/omcu_application.ld")
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
