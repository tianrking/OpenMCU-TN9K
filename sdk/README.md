# OpenMCU 产品应用 SDK

本目录是已固化 OpenMCU-TN9K 产品位流后的客户应用 SDK。日常工作只需编写裸机 **C** 程序，
由 `omcu_add_application()` 生成独立的 `*.omcu` 镜像，再通过 UART0 写入 User Flash。

```text
C 源码 -> RV32IM ELF -> BIN -> .omcu -> UART0 -> User Flash A/B -> SRAM 执行
```

客户应用不会重新编进 FPGA 位流，也不需要调用 FPGA 下载工具。

## 从零开始

请先阅读[《从零开发与烧录 OpenMCU 应用》](../docs/zh-CN/mcu-application-development.md)。它包含：

- Windows 与 Linux 的工具链、环境变量和构建命令；
- 可直接烧录的 `omcu_mcu_hello` Hello World；
- 新建产品应用目标的 CMake 写法；
- `.omcu` 校验、UART0 烧录、串口日志和 A/B 恢复；
- UART0 电气要求、内存上限与实板 HIL 边界。

当前构建链经过验证的语言是 C 与启动汇编；C++ 运行库、异常、RTTI 和动态分配不属于已交付 SDK
能力，应用请按裸机 C 约束设计。

## 唯一的应用目标

在 `sdk/CMakeLists.txt` 中声明自己的应用：

```cmake
omcu_add_application(my_product_app examples/my_product_app/main.c)
```

该函数会自动：

1. 选择应用启动代码和 40 KiB SRAM 链接脚本；
2. 使用 `rv32im` / `ilp32`、`-ffreestanding` 和无标准库链接；
3. 生成 `<target>.elf` 与 `<target>.bin`；
4. 以硬件 ABI、长度和 CRC 封装为 `<target>.omcu`。

不要手写镜像头，应用升级时只把 `.omcu` 交给 `tools/omcu_flash.py`。

## 官方产品应用示例

| 目标 | 目的 |
| --- | --- |
| `omcu_mcu_hello` | UART0 周期输出 Hello World；最小的端到端编译、烧录和日志检查。 |
| `omcu_mcu_blink` | 板载 LED0 闪烁；最小 GPIO 输出应用。 |
| `omcu_uart1_loopback` | UART1 回显模板；UART0 保留给升级，UART1 使用 J5.18/J5.19。 |
| `omcu_pwm1_demo` | 四路共享计数器 PWM 模板。 |
| `omcu_timer1_encoder_demo` | TIMER1 捕获与正交编码器模板。 |
| `omcu_gpio_reliable_input_demo` | GPIO 两级同步、独立滤波、边沿 IRQ 和事件快照。 |
| `omcu_alarm_pulse_demo` | ALARM0 与 PULSE0 低速定时/脉冲测量模板。 |
| `omcu_fault_wdt_supervisor_demo` | FAULT0 门控、故障快照和增强 WDT 模板。 |
| `omcu_bootloader_request_demo` | 应用主动请求进入 UART0 Bootloader 的模板。 |
| `omcu_external_peripherals` | RTC、EEPROM、温度传感器、ADC、DAC 和 W5500 的外置器件模板。 |

所有表中目标均生成 `.omcu`，可在产品位流上独立烧录。

## 编译与产物

Windows：

```powershell
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
python .\tools\omcu_image.py validate --image .\build\sdk\my_product_app.omcu
```

Linux：

```sh
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
python3 ./tools/omcu_image.py validate --image ./build/sdk/my_product_app.omcu
```

构建后常见文件为：

| 文件 | 用途 |
| --- | --- |
| `my_product_app.elf` | 调试、反汇编和链接 map 分析。 |
| `my_product_app.bin` | 原始应用载荷。 |
| `my_product_app.omcu` | 客户升级、现场部署和 A/B 槽写入的唯一镜像。 |

## 外置器件驱动

`omcu_device_drivers` 是 SDK 内置的静态库，提供有界超时的 I2C/SPI 事务，以及 DS3231、AT24Cxx、
TMP102、MCP3008、MCP4921 和 W5500 API。应用按需链接：

```cmake
omcu_add_application(omcu_my_sensor examples/my_sensor/main.c)
target_link_libraries(omcu_my_sensor PRIVATE omcu_device_drivers)
```

公开头文件为 `omcu_bus.h`、`omcu_devices.h`、`omcu.h` 与 `omcu_tn9k.h`。W5500、MCP3008、
MCP4921 的多字节 SPI 帧必须保持片选；请使用驱动库的事务 API。I2C 必须有正确的外部 3.3 V 上拉，
SPI0 与 TF 卡信号组不能同时使用。

驱动可编译、可调用不等于外接模块已经完成实体板 HIL；电平、供电、共地、上拉、线长和实际器件
时序仍须随产品硬件验证。

## ABI、内存与编程约定

| 区域 | 地址 / 大小 | 应用约定 |
| --- | --- | --- |
| Boot ROM | `0x0000_0000`，4 KiB | 固定启动器；客户应用不可修改。 |
| 应用 SRAM | `0x1000_0000`，40 KiB | 代码、数据、栈和中断帧共享。 |
| Bootloader SRAM | 4 KiB | 启动器私有工作区；应用不可使用。 |
| User Flash | `0x2000_0000`，76 KiB | Bootloader 管理的 A/B 应用槽。 |

单镜像最大载荷为 36,800 B。硬件 ABI 为 `0x00000009`；压缩指令 `C` 未启用，必须用当前 SDK
重建镜像，不要手工修改 `.omcu` 的 ABI、入口、长度或 CRC 字段。

除 User Flash 明确规定的擦除命令外，MMIO 配置、命令和 W1C 寄存器均需自然对齐的完整 32-bit
读写；SDK 以 `volatile uint32_t` 完成这些访问。

## UART0 更新与软件恢复

UART0 默认用于 Bootloader、下载和日志。应用要主动进入更新器时，先完成数据落盘和输出安全收尾，
然后调用：

```c
#include "omcu_tn9k.h"

if (omcu_tn9k_request_bootloader()) {
  for (;;) {
  }
}
```

调用成功后 SoC 会复位，Boot ROM 保持 UART0 更新会话。外部复位仍是独立救砖路径。

## 继续阅读

- [从零开发与烧录 OpenMCU 应用](../docs/zh-CN/mcu-application-development.md)
- [外设与 SDK](../docs/zh-CN/peripherals-and-sdk.md)
- [硬件与引脚](../docs/zh-CN/hardware-and-pins.md)
- [中断开发约定](../docs/zh-CN/interrupts.md)
- [外设与引脚完整规格书](../docs/zh-CN/peripheral-pin-specification.md)
