# SDK 兼容性约定

## 面向应用开发者的承诺

应用开发者无需关心程序运行在仿真器、Tang Nano 9K FPGA 配置，还是未来封装的 OpenMCU ASIC 上。SDK 负责选择开发板/芯片目标；在同一个 ABI 主版本内，源代码层的外设 API 保持一致。

## 唯一事实来源

v0 的机器可读规范是 <a href="../spec/omcu-v0.json">spec/omcu-v0.json</a>。<code>scripts/generate-sdk.ps1</code> 将它生成并检入为 <a href="../sdk/include/omcu_regs.h">sdk/include/omcu_regs.h</a>；<code>omcu.h</code> 是建立在这些生成定义之上的少量手写便利层。启用 CI 后，生成器的 <code>-Check</code> 模式是必须通过的门禁。

人工可读的寄存器参考为 <a href="registers.md">寄存器参考</a>。当前完整产品规范以中文主规格书为准：<a href="zh-CN/peripheral-pin-specification.md">OpenMCU-TN9K 外设与引脚完整规格书</a>；数据手册提供产品总览。任何改动都必须将主规格书、JSON、RTL 与 SDK 一并审阅。

下一步会从同一份已审阅规范生成寄存器参考和 Rust 绑定。严禁手工修改生成的寄存器定义，否则会产生难以察觉的软硬件偏差。

## 版本规则

- 硬件在 SYSCTRL 元数据中采用 <code>major.minor</code> ABI 版本；
- 只有不兼容的寄存器行为才允许提升主版本；
- 新的可选模块必须通过特性位图声明；
- SDK 版本固定交叉工具链版本，并记录支持的硬件 ABI 范围。

## 必须提供的公开 SDK 功能

ABI 0.8 SDK 包括设备/特性发现、12-bit GPIO 档案（LED0..5 镜像 GPIO0..5）、两级同步/端口滤波/事件快照、UART0/1、TIMER0/1、两路 ALARM0、单选 PULSE0、FAULT0、轮询式 SPI 单字节和连续 CS 帧传输、可组合的 I2C START/STOP/读写字节辅助函数、增强看门狗、PWM0/四路 PWM1、PINMUX、复位诊断、软件请求 Bootloader，以及可执行的外部 IRQ 入口：<code>omcu_irq_set_mask()</code>、<code>omcu_irq_wait()</code>、<code>omcu_irq_global_enable()</code> 和 IRQCTRL 辅助函数。SDK 固定以 `rv32im` / `ilp32` 构建；压缩指令未启用，ABI 0.7 的 `rv32imc` 镜像必须重新编译。

应用通过提供强符号 <code>omcu_irq_dispatch(uint32_t pending)</code> 实现中断分发。SDK 的向量包装器负责 PicoRV32 自定义指令和全部整数寄存器保护。精确的非标准边界与确认顺序见 <a href="interrupts.md">中断约定</a>。

<code>omcu_tn9k.h</code> 公开 27 MHz 板级定义、逻辑 LED/GPIO 掩码和受控的 UART1/PWM1/TIMER1/PULSE0/FAULT0 pinmux helper，不把 FPGA 封装引脚号泄漏给应用。P1 资源边界是 SDK 合同的一部分：PWM1/TIMER1/ALARM0/PULSE0 的相关数据路径为 16-bit，GPIO/PULSE/FAULT/TIMER1 的滤波语义必须按各自文档理解。I2C 辅助函数在硬件未启用、命令顺序非法或目标 NACK 时返回 <code>false</code>；它们不会暗中伪造事务超时，应用须自行选择外层超时策略。硬件特性位图是唯一权威：SDK 不能只因某个基址被保留，就假定可选外设存在。

受检构建入口是 Windows 的 <code>scripts/build-sdk.ps1</code> 和 Linux/macOS 的 <code>scripts/build-sdk.sh</code>。两者均要求显式 GNU 工具链前缀，并驱动同一份 CMake 工具链文件、链接脚本和生成的寄存器头文件。支持主机的 CI 矩阵会在 Windows、Linux 与 macOS 构建所有 SDK 目标；其通过仍不能替代实板测试。

SDK 还包含 Tang Nano 9K User Flash A/B 路径的独立应用镜像打包器与 UART 串口下载工具，以及外置 DS3231、AT24Cxx、TMP102、MCP3008、MCP4921、W5500 驱动。W5500 是外置 SPI 网络控制器，不是 FPGA MAC/PHY。板卡信息 CLI、标准 QSPI/XIP 路径和符合标准特权 RISC-V 的异常/中断内核仍属未来能力，不应被误认为 ABI 已承诺的属性。
