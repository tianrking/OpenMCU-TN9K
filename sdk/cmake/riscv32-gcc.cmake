set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv32)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# The selected executable prefix is a platform setting, not an application
# setting.  Propagate it into CMake's nested compiler-ABI try-compile project;
# otherwise a user-selected `riscv-none-elf-` prefix is lost and the nested
# configure falls back to the repository's default prefix.
set(CMAKE_TRY_COMPILE_PLATFORM_VARIABLES OMCU_RISCV_PREFIX)

if (NOT DEFINED OMCU_RISCV_PREFIX)
  set(OMCU_RISCV_PREFIX "riscv32-unknown-elf-" CACHE STRING
      "Prefix of the RISC-V GNU toolchain executables")
endif ()

find_program(OMCU_RISCV_GCC NAMES "${OMCU_RISCV_PREFIX}gcc" REQUIRED)
set(CMAKE_C_COMPILER "${OMCU_RISCV_GCC}" CACHE FILEPATH "" FORCE)
set(CMAKE_ASM_COMPILER "${OMCU_RISCV_GCC}" CACHE FILEPATH "" FORCE)
