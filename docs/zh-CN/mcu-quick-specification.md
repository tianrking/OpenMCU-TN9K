# OpenMCU-TN9K MCU 快速规格书

> **文档编号：** OMCU-TN9K-QS-0.9<br>
> **硬件 ABI：** 0x0000_0009（0.9）<br>
> **目标器件：** Tang Nano 9K，GW1NR-LV9QN88PC6/I5（GW1N-9C）<br>
> **适用顶层：** omcu_tn9k_mcu_top

这是给应用、硬件选型和测试快速查阅的摘要。完整中文产品定义先看
[《OpenMCU-TN9K MCU 中文规格书》](datasheet.md)；寄存器字段、完整引脚和电气边界以
[《外设与引脚完整规格书》](peripheral-pin-specification.md) 和
[机器可读 ABI 规范](../../spec/omcu-v0.json) 为准。2×24 实物孔位与电气分级见
[《Tang Nano 9K 外露引脚与 OpenMCU 定义》](tangnano9k-external-pin-contract.md)及
[`spec/tangnano9k-pins.json`](../../spec/tangnano9k-pins.json)。

## 1. 产品定义

| 项目 | 当前产品合同 |
| --- | --- |
| 产品形态 | 固化一次 FPGA 平台；客户应用作为独立 .omcu 镜像持续升级。 |
| CPU | PicoRV32 适配器，RV32IM、小端、ilp32。不支持 C 压缩指令、浮点、原子、特权模式或虚拟内存。 |
| 乘除法 | DSP 加速乘法；32 步 PCPI DIV/DIVU/REM/REMU，保留 RV32M 的除零和溢出语义。 |
| 系统时钟 | 板载 clk_27m_i，27 MHz。ABI 不承诺未经 HIL 的 PLL 或其他时钟源。 |
| 运行计时 | SYSCTRL.RUN_TICKS_LO/HI，64-bit、27 MHz tick；不是 RTC。 |
| Boot ROM | 0x0000_0000，4 KiB。固定 UART0 Bootloader。 |
| SRAM | 0x1000_0000，44 KiB：40 KiB 客户应用运行区 + 4 KiB Bootloader 工作区。 |
| User Flash | 0x2000_0000，76 KiB / 77,824 B：A/B 两个 36 KiB 应用槽；单镜像最大载荷 36,800 B。 |
| MMIO | 0x4000_0000 起；寄存器小端、32-bit、4-byte 对齐。除规定的 User Flash 擦除操作外，配置、命令和 W1C 必须完整 32-bit 写入。 |
| 应用更新 | PC omcu_flash.py 经 UART0 写入非当前 A/B 槽，校验完成才提交；客户日常更新不重新综合 FPGA。 |
| 完整性边界 | 镜像 CRC32、A/B 与回退用于偶发损坏/半写入恢复；不等于签名安全启动。 |

## 2. 时钟、复位与启动

| 事件 | 行为 |
| --- | --- |
| 上电 / 外部复位 | 低有效 resetn_i 异步断言；复位解除后连续等待 3 个干净的 27 MHz 时钟再释放 SoC。 |
| 普通启动 | Boot ROM 短暂监听 UART0，验证 User Flash A/B 槽并把最新有效应用复制到 SRAM 执行。 |
| PC 更新 | 先运行 PC 更新工具、再外部复位即可进入 UART0 会话。 |
| 应用主动更新 | 调用 omcu_tn9k_request_bootloader()，平台记录 SOFTWARE 原因并持续保留 UART0 更新会话。 |
| 看门狗复位 | WDT0 到期且 RESET_ENABLE=1 时重启 SoC，并保留 watchdog 诊断原因。 |
| 救砖边界 | 外部复位始终有效；真实 User Flash 擦写、掉电和冷启动仍需实体板 HIL。 |

## 3. 片上外设

| 外设 | 基址 | 主要能力 | 主要限制 |
| --- | ---: | --- | --- |
| GPIO0 | 0x4000_0000 | 12 路 GPIO、OE/高阻、两级同步、共享或每针 2/4/8 样本滤波、边沿 IRQ、事件快照；GPIO0..5 镜像 LED0..5。 | 非 ADC、非高速采样；GPIO3..11 与 RGB LCD 共线。 |
| UART0 | 0x4000_1000 | 8N1 RX/TX、RX IRQ、默认 115200。 | Bootloader、恢复和默认日志通道；业务复用后应通过 SYSCTRL 返回 Bootloader。 |
| TIMER0 | 0x4000_2000 | 32-bit 比较、自动重装、IRQ。 | 基础软件定时器，不是 RTC。 |
| SPI0 | 0x4000_3000 | mode 0 主机、逐字节传输、显式多字节 CS 保持。 | 与 TF 信号组共享；不与 microSD 并用。 |
| I2C0 | 0x4000_4000 | 单主机开漏 START/STOP、逐字节读写。 | 外部 3.3 V 上拉由板级提供。 |
| WDT0 | 0x4000_5000 | 超时、预警 IRQ、窗口、最多 8 个 heartbeat、复位请求。 | 非独立安全时钟、非安全认证监督器。 |
| PWM0 | 0x4000_6000 | 单路边沿对齐 PWM。 | 非互补功率/栅极驱动。 |
| IRQCTRL | 0x4000_7000 | 11 个外部源的 pending、enable、force、优先级观察。 | 固定 PicoRV32 IRQ ABI；不是 PLIC。 |
| UART1 | 0x4000_8000 | 无大 FIFO 的 RX/TX + RX IRQ。 | 先由 PINMUX 取得 GPIO10/11。 |
| TIMER1 | 0x4000_9000 | 16-bit 比较、双输入捕获、数字滤波、正交编码器。 | 非异步高速计数器。 |
| PWM1 | 0x4000_A000 | 四路共享 16-bit 计数器 PWM，独立 duty/invert。 | 无互补、死区、影子更新或功率级保护。 |
| PINMUX | 0x4000_B000 | 把已审查 J5 pad 显式交给 UART1、PWM1、TIMER1、PULSE0 或 FAULT0。 | 同一 pad 的 GPIO/RGB LCD/复用外设不能并用。 |
| ALARM0 | 0x4000_C000 | 基于 TIMER0 时基的两路并行 16-bit compare，可 one-shot 或周期触发。 | 不带 FIFO，不是 RTC。 |
| PULSE0 | 0x4000_D000 | 从 GPIO0..2 单选一路，低速脉冲计数、周期和最后 tick。 | 非三路并行、非高速输入。 |
| FAULT0 | 0x4000_E000 | GPIO3 故障锁存、PWM 拉低、GPIO 高阻、强制快照。 | 仅 FPGA 逻辑级门控，不能称功能安全。 |
| SYSCTRL | 0x4000_F000 | CHIP_ID、ABI、特性、内存、复位原因、运行 tick、复位计数和 Bootloader 请求。 | 诊断语义以产品顶层为准。 |
| User Flash 控制器 | 0x2000_0000 窗口 | 76 KiB 应用 A/B 存储和 Bootloader 更新协议。 | 不等于 FPGA 配置 Flash；真实擦写/寿命/掉电未 HIL。 |

SYSCTRL.FEATURES 在产品位流中为 0x000F_FFFF（bit 0..19 都存在）。应用应先检查
CHIP_ID、ABI 主版本和 feature 位，不能假定较小 bring-up 位流也具备这些外设。

## 4. 中断

IRQCTRL 固定映射到 PicoRV32 CPU IRQ bit 8..18：

| CPU IRQ bit | 来源 | 清除 / 服务原则 |
| ---: | --- | --- |
| 8 | GPIO0 边沿 | 读快照后按 GPIO 的 W1C 合同确认。 |
| 9 | UART0 RX | 尽快读取接收数据并确认状态。 |
| 10 | TIMER0 compare | 按 TIMER0 pending/W1C 合同确认。 |
| 11 | SPI0 DONE | 完成事务后确认。 |
| 12 | I2C0 DONE / 错误 | 读取状态、结束总线状态后确认。 |
| 13 | WDT0 到期 | 记录原因；不要把 IRQ 当成已安全复位。 |
| 14 | UART1 RX | 尽快读取，因 UART1 无大 FIFO。 |
| 15 | TIMER1 compare / capture / encoder 事件 | 读取捕获/状态，再按 W1C 合同确认。 |
| 16 | ALARM0 任一 compare pending | 分辨 ch0/ch1 后确认。 |
| 17 | PULSE0 测量边沿 | 读取 count/period/last tick 后确认。 |
| 18 | FAULT0 首次锁存 | 先保障外部负载安全，再按故障恢复流程处理。 |

SDK 入口为 omcu_irq_set_mask()、omcu_irq_wait()、omcu_irq_global_enable() 和 ISR
分发钩子。它不是标准 CSR/PLIC 软件模型，详见[中断开发约定](interrupts.md)。

## 5. 已公开 I/O

| 功能 / 逻辑 GPIO | 实物左排（原理图 J5） | package pad | PINMUX 后用途 |
| --- | --- | --- | --- |
| SPI0 CS/MOSI/SCK/MISO | L1..L4（J5.1..4） | 38 / 37 / 36 / 39 | 固定 mode-0 主机，与 TF 卡共享。 |
| PWM0 | L5（J5.5） | 25 | 固定单路逻辑 PWM 输出。 |
| I2C0 SCL/SDA | L6..L7（J5.6..7） | 26 / 27 | 固定开漏主机，必须外部 3.3 V 上拉。 |
| GPIO0..2 | L8..L10（J5.8..10） | 28 / 29 / 30 | 普通 GPIO 或 PULSE0 单选输入。 |
| GPIO3..7 | L11..L15（J5.11..15） | 33 / 34 / 40 / 35 / 41 | 普通 GPIO；GPIO3 是 FAULT0，GPIO4..7 是 PWM1 CH0..3。 |
| GPIO8..9 | L16..L17（J5.16..17） | 42 / 51 | 普通 GPIO 或 TIMER1 A/B。 |
| GPIO10..11 | L18..L19（J5.18..19） | 53 / 54 | 普通 GPIO 或 UART1 TX/RX。 |

这些路线仅代表 RTL、CST 和 P&R 已约束的公开合同。J6/HDMI/JTAG/配置 pin、板载配置 Flash、
PSRAM、TF、RGB LCD 和“空闲 package pin”不因此成为可安全使用的 GPIO；仍须确认板卡 revision、
3.3 V bank、电流、接地和共线器件。

当前公开信号在实物上是连续的左排 `L1..L19`；这 19 根都能从 2.54 mm 孔位接触。`L20..L22`
以及右排若干 3.3 V 网络虽物理外露，但 ABI 0.9 没有对应 MMIO GPIO bit，属于保留而非可开发引脚；
右排 `R2..R9` 为 1.8 V，HDMI 共线组还带板级上拉，均不得按普通 3.3 V GPIO 使用。

## 6. SDK 与应用开发

SDK 已提供裸机启动代码、链接脚本、寄存器头、IRQ 包装、Bootloader 协议工具和下列应用示例：
mcu_hello、mcu_blink、UART1 回环、PWM1、TIMER1 编码器、GPIO 可靠输入、ALARM/PULSE、FAULT/WDT、
Bootloader 请求以及 DS3231/AT24Cxx/TMP102/MCP3008/MCP4921/W5500 外置器件。

~~~powershell
# 平台/SDK 工程：构建 Boot ROM 和所有独立应用
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-

# 客户工程引用 sdk/cmake/OpenMCUSDK.cmake 并通过 omcu_add_application() 声明后：
python -m pip install pyserial
.\build.ps1
.\flash.ps1 -Port COM5
~~~

应用使用 RV32IM / ilp32 编译；旧 rv32imc 或旧 ABI 镜像会被产品 Bootloader 拒绝。SDK 的
构建和数字仿真已覆盖，但外置模块的电气、ACK、波形、链路与异常恢复仍需 HIL。

## 7. 资源结论：为什么不把 DFF 强行拉到 5k

已发布 ABI 0.9 的最终可 P&R 基线为 LUT4 7,211 / 8,640（83.46%）、DFF 2,631 / 6,480
（40.60%）、BSRAM 24 / 26（92.31%）。DFF 是触发器数量，不是独立可兑换的“存储额度”：
一个可读、可触发、可停止的寄存器记录器还需要 LUT、选择/地址逻辑、控制扇出和可达布线。

在同一完整产品（4 KiB ROM、44 KiB SRAM、全部 ABI 0.9 外设）的 GPIO 12-bit DFF 流式记录器探索中，
以下候选都完成综合但 **P&R 失败**，因此没有加入 ABI、寄存器或 SDK：

| 候选记录深度 | 综合 LUT4 | 综合 DFF | P&R 结论 |
| ---: | ---: | ---: | --- |
| 200 样本 | 7,521 | 5,207 | 无合法布局/布线。 |
| 184 样本 | 7,484 | 5,015 | 无合法布局/布线。 |
| 128 样本 | 7,497 | 4,343 | 无合法布局/布线；也尝试 placer-heap-beta=1.00 和不同 seed。 |
| 64 样本 | 7,509 | 3,575 | 无合法布局/布线。 |
| 32 样本 | 7,523 | 3,191 | 无合法布局/布线。 |

所以答案是：**不能把 DFF 数字硬拉到 5,000 后仍把它称为可交付 MCU。** 这个实现已经是
LUT/BSRAM/局部路由共同受限的产品；没有功能收益的 dummy DFF 更不能作为“资源利用率优化”加入。
任何新功能只能以“RTL + SDK + 回归 + 精确目标器件 P&R + HIL”的整条证据链重新进入 ABI。

## 8. 验证状态

| 层级 | 当前结论 |
| --- | --- |
| 规格、SDK、Boot ROM | 已自动化检查。 |
| RTL / 编译固件仿真 | 36/36 smoke 目标通过；Python 镜像/协议/自检转录测试 17/17 通过。 |
| FPGA 产品 P&R / packing | 同一 ABI 0.9 源码已通过精确 GW1NR 目标器件；27 MHz 约束下报告 43.050 MHz、13.808 ns 裕量。 |
| GitHub Actions | 每次 push/PR 会执行规格、全部 RTL、全 SDK、已编译固件仿真、工具协议测试、跨主机 SDK 构建，以及 Windows 上的 YoWASP 产品 P&R/packing 并上传 manifest/报告/位流。 |
| 实体板 HIL / 量产 | 一块 Tang Nano 9K 的配置固化、板载 UART0 289/289 双向回显、User Flash A/B、仓库外模板应用、无夹具核心自检 24/24 和最终位流六线回环 8/8 已通过；目标模块、多板、分阶段断电、寿命、EMC/ESD 与安全认证仍未完成。 |

完整证据、命令和 HIL 清单见[验证与发布状态](validation-and-release.md)及
[测试计划](../../tests/README.md)。
