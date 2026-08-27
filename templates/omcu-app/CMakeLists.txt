cmake_minimum_required(VERSION 3.20)

# Point this project at a cloned/released OpenMCU SDK without copying SDK
# sources into the application repository. The toolchain must be selected
# before project() enables C and assembly.
if (NOT DEFINED OMCU_SDK_PATH AND DEFINED ENV{OMCU_SDK_PATH})
  set(OMCU_SDK_PATH "$ENV{OMCU_SDK_PATH}")
endif ()
if (NOT OMCU_SDK_PATH)
  message(FATAL_ERROR
    "Set OMCU_SDK_PATH to the OpenMCU-TN9K sdk directory")
endif ()
get_filename_component(OMCU_SDK_PATH "${OMCU_SDK_PATH}" ABSOLUTE)
if (NOT DEFINED CMAKE_TOOLCHAIN_FILE)
  set(CMAKE_TOOLCHAIN_FILE
      "${OMCU_SDK_PATH}/cmake/riscv32-gcc.cmake"
      CACHE FILEPATH "OpenMCU RISC-V toolchain")
endif ()

project(my_omcu_app LANGUAGES C ASM)

include("${OMCU_SDK_PATH}/cmake/OpenMCUSDK.cmake")

# Add application-owned source files here. The SDK supplies startup, the IRQ
# wrapper, linker contract and .omcu image packer.
omcu_add_application(my_omcu_app
  src/main.c
)

# For RTC/EEPROM/sensor/ADC/DAC/W5500 helpers, uncomment:
# target_link_libraries(my_omcu_app PRIVATE OpenMCU::device_drivers)
