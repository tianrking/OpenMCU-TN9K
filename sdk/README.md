# OpenMCU RV32IM SDK

本 SDK 为 OpenMCU Tang Nano 9K 产品目标构建无操作系统的 `rv32im` / `ilp32` 固件。它区分三种完全不同的产物，避免把客户应用误当成 FPGA ROM 输入。

## 三种产物，三个用途

| CMake 目标类型 | 典型产物 | 用途 | 客户日常使用？ |
| --- | --- | --- | --- |
| `omcu_add_bootloader()` | `omcu_bootloader.elf` / `.hex` | 放入产品 FPGA 的 4 KiB Boot ROM | 否；随 FPGA 平台固化 |
| `omcu_add_application()` | `my_app.elf` / `.bin` / `.omcu` | UART 写入独立 User Flash 后从 SRAM 运行 | **是** |
| `omcu_add_firmware()` | `*.elf` / `*.hex` | 旧式 ROM、RTL 和 FPGA bring-up 回归 | 否；不得当作客户升级包 |

`omcu_mcu_blink` 是最小的独立 MCU 应用示例。它和以后客户写的应用一样，生成 `*.omcu`，不需要重新构建 FPGA 位流。

CPU、内存、全部寄存器、引脚和明确不提供的能力见 [中文工程数据手册](../docs/zh-CN/datasheet.md)。

## 环境准备

- CMake 3.20 或更新版本、Ninja；
- 可用的 GNU bare-metal RISC-V `gcc` 与 `objcopy`；
- PicoRV32 子模块处于记录的版本；
- 只有实际串口升级时才需要 Python 3 和 `pyserial`。

推荐使用 xPack 的 `riscv-none-elf-` 前缀。Windows 示例：

```powershell
git submodule update --init --recursive
$env:PATH = 'C:\toolchains\riscv-none-elf\bin;' + $env:PATH
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
```

如果 CMake 或 Ninja 不在 `PATH`，给包装脚本传入 `-Cmake`、`-Ninja` 的绝对路径。`-Fresh` 仅会清理明确指定的 SDK 构建目录，要求 CMake 3.24 或更新版本。

Linux/macOS 使用同一 CMake 工程和链接脚本：

```sh
git submodule update --init --recursive
export PATH="/opt/xpack-riscv-none-elf/bin:$PATH"
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
```

## 新建一个可独立烧录的应用

1. 新建 `sdk/examples/my_product_app/main.c`。
2. 在 `sdk/CMakeLists.txt` 中添加：

   ```cmake
   omcu_add_application(my_product_app examples/my_product_app/main.c)
   ```

3. 构建并校验生成物：

   ```powershell
   .\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
   python .\tools\omcu_image.py inspect --image .\build\sdk\my_product_app.omcu
   ```

4. 将 `.omcu` 交给已固化 FPGA 平台的串口升级器：

   ```powershell
   python .\tools\omcu_flash.py --port COM5 `
     --image .\build\sdk\my_product_app.omcu
   ```

详细升级流程、复位窗口、掉电恢复和安全限制见 [中文独立固件指南](../docs/zh-CN/mcu-firmware-update.md)。

## 内存与 ABI 约定

| 区域 | 地址 / 大小 | 归属 |
| --- | --- | --- |
| Boot ROM | `0x0000_0000`，4 KiB | FPGA 平台内固定启动器 |
| 应用 SRAM | `0x1000_0000`，40 KiB | `omcu_add_application()` 的代码、数据、栈和中断帧 |
| 启动器 SRAM | 应用区顶部之外的 4 KiB | 启动器校验、复制和 UART 会话；应用不可使用 |
| User Flash | `0x2000_0000`，76 KiB | A/B 应用槽；由启动器控制 |

应用镜像固定从 `0x1000_0000` 装载和入口，最大已对齐载荷为 36,800 字节。镜像包含硬件 ABI `0x00000008`、载荷长度、CRC32 和状态字；不要手工修改头部或绕开 `tools/omcu_image.py`。ABI 0.8 对应 RV32IM；旧 `rv32imc` / ABI 0.7 镜像会被 Bootloader 拒绝，重新编译源代码即可迁移。

`omcu_tn9k.h` 只定义 27 MHz 时钟和逻辑 LED/GPIO 位掩码，不暴露 FPGA 封装管脚。物理管脚、电平和外设冲突请看 [Tang Nano 9K 平台说明](../rtl/platform/tangnano9k/README.md)。

## 示例目录

| 目标 | 目的 |
| --- | --- |
| `omcu_mcu_blink` | 独立 `.omcu` 形式的 LED 闪烁示例。 |
| `omcu_uart1_loopback` | 独立 `.omcu` 的 UART1 回显/HIL 示例；UART0 保持给升级器。 |
| `omcu_pwm1_demo` | 独立 `.omcu` 的四路共享计数器 PWM/HIL 示例。 |
| `omcu_timer1_encoder_demo` | 独立 `.omcu` 的 TIMER1 捕获/正交编码器模板；GPIO8/9 经输入 pinmux 使用。 |
| `omcu_gpio_reliable_input_demo` | 12 路 GPIO 的两级同步、端口滤波、边沿 IRQ 和事件快照模板。 |
| `omcu_alarm_pulse_demo` | 两路并行 ALARM0 与 GPIO0..2 中单选 PULSE0 的低速测量模板。 |
| `omcu_fault_wdt_supervisor_demo` | GPIO3 FAULT0 门控/快照与增强 WDT 的窗口、预警和 heartbeat 模板。 |
| `omcu_bootloader_request_demo` | 独立 `.omcu` 的软件请求回 UART0 Bootloader 示例；只适用于产品 MCU 位流。 |
| `omcu_blink` | 旧式 ROM LED 回归。 |
| `omcu_uart_hello` | UART0 启动文字。 |
| `omcu_isa_smoke` | 编译器、RV32IM 指令（含乘除法）和启动代码集成检查。 |
| `omcu_peripheral_smoke` | GPIO、SPI0、PWM0、WDT0 集成检查。 |
| `omcu_i2c_smoke` | I2C START/写/读/STOP 夹具检查。 |
| `omcu_irq_smoke` | TIMER0 到 IRQCTRL、固定向量、C ISR、`RETIRQ` 的全链路检查。 |
| `omcu_wdt_reset_smoke` | 经 Tang 封装的看门狗复位检查。 |
| `omcu_tn9k_board_demo` | UART、PWM、逻辑 LED、扩展 GPIO 和 WDT 的板级 bring-up 示例。 |
| `omcu_external_peripherals` | P0 外置 RTC、温度传感器和 W5500 静态网络配置模板；生成独立 `.omcu`。 |

中断是 PicoRV32 自定义 ABI，而不是特权 RISC-V CSR/PLIC API。应用启用中断前必须阅读 [`docs/interrupts.md`](../docs/interrupts.md)。

## P0 外置器件驱动

`omcu_device_drivers` 是 SDK 内置的无动态内存静态库。客户应用在 CMake 中显式链接它：

```cmake
omcu_add_application(omcu_my_sensor examples/my_sensor/main.c)
target_link_libraries(omcu_my_sensor PRIVATE omcu_device_drivers)
```

公开头文件为 `omcu_bus.h` 与 `omcu_devices.h`：提供有界超时的 I2C/SPI 事务，DS3231 RTC、
AT24Cxx EEPROM、TMP102 温度传感器、MCP3008 ADC、MCP4921 DAC，以及 W5500 的初始化、
socket 打开/连接/收发 API。W5500、MCP3008 和 MCP4921 的帧会通过 SPI0 `CS_HOLD` 保持
片选，不能再把每字节自动释放 CS 的旧语义误用于这些器件。

这些是可编译、可调用的外设驱动，不等于目标模块已完成实体板 HIL。使用前必须确认 3.3 V、
共地、I2C 外部上拉，以及 SPI0 与 TF 卡不能同时使用；W5500 的 TX/RX 缓冲区总量还必须由
应用控制在芯片的 16 KiB 总预算内。

## UART1 第二路串口

`omcu_uart1_loopback` 是独立应用镜像，不会重新编进 FPGA。它检查
`OMCU_FEATURE_UART1 | OMCU_FEATURE_PINMUX`，把 UART1 配为 115200 8-N-1，并显式将
Tang Nano 9K 的 GPIO10/J5.18 设为 TX、GPIO11/J5.19 设为 RX。烧录方式仍是先由 UART0
Bootloader 写入它的 `.omcu`，之后再把第二只 3.3 V TTL 串口接到 J5.18/J5.19 验证回显。

UART1 没有 FIFO；主循环必须及时读取 `DATA`，否则下一字节会置 `RX_OVERRUN`。使用 RGB LCD
时不能启用这组 pinmux。真实波特率、电平与共线冲突的 HIL 尚未完成，不能把该示例的编译或
数字仿真写成实体板验证。

## PWM1 四通道共享计数器

`omcu_pwm1_demo` 生成独立 `.omcu`，演示 GPIO4..7/J5.12..15 的 PWM1 CH0..3。调用
`omcu_tn9k_pwm1_configure()` 会先完成安全的低电平寄存器配置，再显式交给 pinmux；四个 duty
使用同一个 **16-bit** 计数器和周期（0..65535），适合同步灯带/舵机/低压驱动的逻辑输入。它不具备死区、互补对、
制动、DMA 或高压功率级保护，不能直接驱动电机/继电器/MOSFET gate。

测试时 UART0 保留给下载器，先以示波器或逻辑分析仪验证 J5.12..15 的频率、四路占空比和
`CTRL.ENABLE=0` 后低电平。该组与 RGB LCD 共线，HIL 完成前不能声称板级或功率级已支持。

## TIMER1 捕获与正交编码器

`omcu_timer1_encoder_demo` 是独立应用镜像。它检查 `OMCU_FEATURE_TIMER1 |
OMCU_FEATURE_PINMUX`，配置两级同步、`FILTER=4` 的稳定样本滤波、A/B 捕获和 Gray 正交解码，
然后将 GPIO8/J5.16、GPIO9/J5.17 归 TIMER1 输入所有。正向约定是
`00 -> 01 -> 11 -> 10 -> 00`；位置是有符号 16-bit 环绕值，helper 将读回值符号扩展为 `int32_t`，
`STATUS.ENCODER_ILLEGAL` 可用于发现非 Gray/同时双边沿变化。TIMER1 的 compare/capture/count 也均为
16-bit，`FILTER` 为 8-bit，API 参数刻意使用 `uint16_t`/`uint8_t`，避免未实现高位的错误预期。

`FILTER=N` 需要 `N+1` 个连续同步样本，并不是固定毫秒去抖器，也没有 DMA、FIFO、高速异步
计数或速度计算。J5.16/J5.17 与 RGB LCD 共线；先保留 UART0 下载通道，再用 3.3 V、共地的
低速已知 Gray 序列和逻辑分析仪完成实板 HIL。当前已通过 RTL、MMIO、编译固件到最终 pad 的
数字仿真，不应把它表述为真实编码器、电压或抗噪 HIL。

## GPIO 可靠性、ALARM0、PULSE0、FAULT0 与增强 WDT

`omcu_gpio_reliable_input_demo` 展示 `omcu_gpio0_set_filter_cycles()`、
`omcu_gpio_snapshot_arm()` 和 `omcu_gpio_snapshot_read()`：GPIO0 的每根输入都会先过两级同步，
但额外的稳定滤波窗口由整个 12-bit 端口共享；一根引脚变化会重启窗口。快照记录边沿、过滤后输入、
`RUN_TICKS`、IRQCTRL active 与 reset cause；若 `forced=true`，代表 FAULT0 的优先捕获覆盖了普通快照。

`omcu_alarm_pulse_demo` 演示复用 TIMER0 时基的两个并行 16-bit ALARM0 通道，以及 PULSE0 在 GPIO0/J5.8、GPIO1/J5.9、
GPIO2/J5.10 中单选一路的 16-bit 边沿计数/周期。PULSE0 不是异步高速计数器；接管前会释放三根 GPIO
输出，外部信号必须是经审核、3.3 V、共地、低速的逻辑输入。

`omcu_fault_wdt_supervisor_demo` 让 GPIO3/J5.11 成为 FAULT0 输入。故障锁存可选择拉低 PWM0/PWM1、
释放全部公开 GPIO 为高阻并强制事件快照；它仍不是外部急停、冗余安全控制或认证功能安全。增强 WDT
支持 pretimeout、最小喂狗窗口和最多 8 个任务 heartbeat；只应在所有关键任务完成健康检查后喂狗。
这些三个示例均已覆盖数字 RTL/SDK 构建，实际电平、脉冲范围、门控波形和复位时序仍需 HIL。

## 复位诊断与软件回 Bootloader

产品 Tang 位流会报告 `OMCU_FEATURE_DIAGNOSTICS`。`SYSCTRL` 提供上一次复位原因、从当前
SoC 释放复位开始的 64-bit `RUN_TICKS`、自外部复位以来的 watchdog/software `RESET_COUNT`，
以及受完整魔数保护的 `BOOT_CTRL`。建议使用公开 helper：

```c
uint32_t cause = omcu_sysctrl_reset_cause();
uint32_t reset_count = omcu_sysctrl_reset_count();
uint64_t ticks = omcu_sysctrl_run_ticks();

if (omcu_tn9k_request_bootloader()) {
  for (;;) {
  }
}
```

`omcu_tn9k_request_bootloader()` 只在同时具备诊断和 User Flash 产品特性的位流上成功。成功代表
命令已经发出，随后 SoC 会复位；不要把它放在仍需继续执行的关键写入之前。Boot ROM 会确认待处理
请求并保持 UART0 会话，主机可直接使用现有 `omcu_flash.py` 更新；外部复位和空白设备的持续监听
仍是独立恢复路径。`RUN_TICKS` 是 27 MHz SoC 时钟 tick，不是 RTC 秒表；helper 用高/低/高读取
避免 32-bit rollover 撕裂。诊断寄存器的 RTL 与 Boot ROM 路径有数字回归，实际复位键、串口和
User Flash 恢复行为仍需要实板 HIL。
