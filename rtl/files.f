# Compile order for the executable v0 simulation / FPGA-bring-up system.
rtl/bus/omcu_mmio_pkg.sv
third_party/picorv32/picorv32.v
rtl/peripherals/omcu_gpio.sv
rtl/peripherals/omcu_uart.sv
rtl/peripherals/omcu_timer.sv
rtl/peripherals/omcu_spi.sv
rtl/peripherals/omcu_i2c.sv
rtl/peripherals/omcu_wdt.sv
rtl/peripherals/omcu_pwm.sv
rtl/peripherals/omcu_irq_ctrl.sv
rtl/peripherals/omcu_sysctrl.sv
rtl/peripherals/omcu_user_flash.sv
rtl/bus/omcu_mmio_fabric.sv
rtl/cpu/omcu_picorv32_system.sv
