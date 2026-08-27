cmake_minimum_required(VERSION 3.20)

project(OpenMCU_SDK LANGUAGES C ASM)

include(cmake/OpenMCUSDK.cmake)

omcu_add_firmware(omcu_blink examples/blink/main.c)
omcu_add_firmware(omcu_uart_hello examples/uart_hello/main.c)
omcu_add_firmware(omcu_isa_smoke examples/isa_smoke/main.c)
omcu_add_firmware(omcu_peripheral_smoke examples/peripheral_smoke/main.c)
omcu_add_firmware(omcu_i2c_smoke examples/i2c_smoke/main.c)
omcu_add_firmware(omcu_wdt_reset_smoke examples/wdt_reset_smoke/main.c)
omcu_add_firmware(omcu_tn9k_board_demo examples/tn9k_board_demo/main.c)
omcu_add_firmware(omcu_irq_smoke examples/irq_smoke/main.c)
omcu_add_firmware(omcu_pwm1_smoke examples/pwm1_smoke/main.c)
omcu_add_firmware(omcu_timer1_smoke examples/timer1_smoke/main.c)
omcu_add_firmware(omcu_boot_request_smoke examples/boot_request_smoke/main.c)

omcu_add_bootloader(omcu_bootloader)
add_custom_command(TARGET omcu_bootloader POST_BUILD
  COMMAND "${Python3_EXECUTABLE}" "${OMCU_BOOTLOADER_FIXTURE_TOOL}"
          --generated "${CMAKE_CURRENT_BINARY_DIR}/omcu_bootloader.hex"
          --fixture "${OMCU_BOOTLOADER_FIXTURE}"
  COMMENT "Checking the checked-in Tang Nano 9K Boot ROM fixture"
  VERBATIM
)
omcu_add_application(omcu_mcu_blink examples/mcu_blink/main.c)
omcu_add_application(omcu_mcu_hello examples/mcu_hello/main.c)
omcu_add_application(omcu_mcu_uart_echo examples/mcu_uart_echo/main.c)
omcu_add_application(omcu_mcu_selftest examples/mcu_selftest/main.c)
omcu_add_application(omcu_mcu_loopback_selftest examples/mcu_loopback_selftest/main.c)
omcu_add_application(omcu_uart1_loopback examples/uart1_loopback/main.c)
omcu_add_application(omcu_pwm1_demo examples/pwm1_demo/main.c)
omcu_add_application(omcu_timer1_encoder_demo examples/timer1_encoder_demo/main.c)
omcu_add_application(omcu_gpio_reliable_input_demo examples/gpio_reliable_input_demo/main.c)
omcu_add_application(omcu_alarm_pulse_demo examples/alarm_pulse_demo/main.c)
omcu_add_application(omcu_fault_wdt_supervisor_demo examples/fault_wdt_supervisor_demo/main.c)
omcu_add_application(omcu_bootloader_request_demo examples/bootloader_request_demo/main.c)
omcu_add_application(omcu_external_peripherals examples/external_peripherals/main.c)
target_link_libraries(omcu_external_peripherals PRIVATE omcu_device_drivers)
