# Tang Nano 9K 资源与外设扩展：P0/P1 实施闭环

> **适用基线：** `omcu_tn9k_mcu_top`、硬件 ABI `0.6`、
> `GW1NR-LV9QN88PC6/I5`（GW1N-9C）
> **状态：** 本页列出的 P0/P1 已完成 RTL/SDK/回归与目标器件 P&R 收口；所有实体板电气、
> 总线目标和 User Flash HIL 仍为发布门禁，不能因 P&R 通过而标为已验证。

本文件原本是候选能力清单；现在保留决策理由、记录本次实现的准确范围，并把后续高风险方向
明确留在 P2/P3。它不把“芯片还有 IOB”误写成“开发板可以安全使用”，也不把“编译通过”误写成
“客户可交付”。

## 1. 本次资源结论

完整 P0/P1 档案在没有新增 BSRAM 的条件下放入 Tang Nano 9K 产品顶层。最终产品构建的真实
哈希、工具版本、时序和资源必须以同目录的 `omcu_tn9k_mcu_manifest.json` 为准；本次收口的
P&R 资源基线为：

| 资源 | 已用 / 总量 | 结论 |
| --- | ---: | --- |
| LUT4 | 6,844 / 8,640（79.21%） | 已超过原路线图的 15% 余量目标，但仍保留 1,796 LUT；后续功能必须先独立 P&R。 |
| DFF | 2,154 / 6,480（33.24%） | 不是当前主要瓶颈。 |
| BSRAM | 26 / 26（100.00%） | **零余量**；禁止把未来能力建立在大 FIFO、缓存或新片上 RAM 上。 |
| ALU | 1,464 / 6,480（22.59%） | 记录用，不应替代 LUT/时序决策。 |
| MULT36X36 | 1 / 5（20.00%） | 快速乘法器保留。 |
| IOB | 15 / 276（5.43%） | 封装余量不等于 Tang 板上可安全暴露的引脚数。 |
| 时序 | 27.000 MHz 约束，40.357 MHz 实现 | 报告裕量 12.258 ns；每次 RTL 改动必须重新测量。 |

### 1.1 为什么与初始估算不同

原路线图预留约 700 LUT，是在基础 CPU 配置下的审慎估算。完整 P1 功能加上 GPIO、
UART1、PWM1、TIMER1、诊断和产品 Bootloader 集成后，第一次直接实现超过器件 LUT 容量。
本次没有删掉客户功能，而是做了明确、可文档化的资源取舍：

| 取舍 | 保留的产品行为 | 代价 / 边界 |
| --- | --- | --- |
| PWM1/TIMER1 数据路径为 16-bit | 四路同步 PWM、定时、双捕获、正交编码仍完整 | `PERIOD`、`DUTY`、`COUNT`、时间戳和位置为低 16-bit；`FILTER` 为 8-bit。 |
| 单端口寄存器堆 | `RV32IMC` 应用二进制兼容 | 部分寄存器相关指令增加周期。 |
| 迭代移位器 | 所有标准移位指令语义保留 | 变量移位不再是单周期。 |
| 紧凑 32 步 PCPI 除法器 | `DIV/DIVU/REM/REMU` 语义保留，含零除/溢出边界 | 除法是迭代操作；不适合高吞吐 DSP。 |
| 禁用 PicoRV32 内部 `cycle/instret` 计数器 | 统一使用 64-bit SYSCTRL 运行 tick | 这些 CSR 不是公开 ABI。 |

这不是隐藏的“性能优化”声明：P&R 只证明资源和时序；具体应用性能仍需在目标固件和实体板上
测量。完整 CPU/外设合同见[工程数据手册](datasheet.md)。

## 2. 用户提出的候选能力：完成状态

| 候选能力 | RTL / 存储影响 | 本次实现 | 验证状态 | 结论 |
| --- | --- | --- | --- | --- |
| SPI/I2C ADC、DAC、RTC、EEPROM、传感器 SDK | 无新 FPGA RTL | DS3231、AT24Cxx、TMP102、MCP3008、MCP4921 驱动与示例/SDK 构建 | 源码、编译、总线 RTL 回归；真实器件 HIL 待做 | **P0 完成（预 HIL）** |
| W5500 外置 SPI 网络控制器 | 无新 FPGA RTL；可选 GPIO IRQ | W5500 初始化、寄存器、TCP/UDP socket API；SPI 连续 CS 帧支持 | 驱动/RTL 回归；模块链路、TF 互斥、IRQ HIL 待做 | **P0 完成（预 HIL）**；不是片上 MAC/PHY |
| GPIO 扩展档案 | 顶层/OE/IRQ 位宽，低 | 12 路外扩 GPIO（总 GPIO 寄存器宽度 18），J5.8..19 受控映射 | RTL、CST、固件仿真、P&R；电压/RGB 共线 HIL 待做 | **P1 完成（预 HIL）** |
| UART1 | 无大 FIFO，低到中 | RX/TX + RX IRQ，GPIO10/11 显式 PINMUX，UART0 未受影响 | RTL、固件仿真、P&R；串口实测待做 | **P1 完成（预 HIL）** |
| PWM1 | 低 | 四路共享 16-bit 计数器/周期，独立 duty/invert，GPIO4..7 PINMUX | RTL、固件波形仿真、P&R；示波器/负载 HIL 待做 | **P1 完成（预 HIL）** |
| TIMER1/输入捕获/正交编码器 | 低到中 | 双两级同步输入、0..255 稳定滤波、16-bit 捕获/比较、Gray 正交诊断 | RTL、编译固件、P&R；编码器/噪声 HIL 待做 | **P1 完成（预 HIL）** |
| 复位/Bootloader/诊断 | 低，无新 I/O | RESET_CAUSE、RUN_TICKS、RESET_COUNT、`BOOT_CTRL`、Boot ROM 强制更新会话、SDK helper | RTL/Boot ROM/固件顶层回归、P&R；真实复位/UART HIL 待做 | **P1 完成（预 HIL）** |

### P0 的真正含义

“P0 已实现”只表示 SDK 已提供接口和可编译实现，SPI0/I2C0 的已有数字逻辑没有为每个器件
新增 FPGA RTL。每一个目标模块仍必须完成地址/ACK/电平/上拉/波形/异常断开/掉电的 HIL。
W5500 使用外置 3.3 V 控制器，既不会消耗 FPGA MAC/PHY 资源，也不应被描述为“片上以太网”。

## 3. 已公开 I/O 档案

只公开经过顶层、CST、Bank 电压说明和数字回归共同约束的 J5 路由：

| 路由 | J5 | package pad | 所有权 / 禁止条件 |
| --- | --- | --- | --- |
| GPIO0..2 | 8..10 | 28 / 29 / 30 | 公开 3.3 V 普通 GPIO。 |
| GPIO3..11 | 11..19 | 33 / 34 / 40 / 35 / 41 / 42 / 51 / 53 / 54 | 3.3 V 但与 RGB LCD 共线；不能同时使用 RGB LCD。 |
| PWM1 CH0..3 | 12..15 | 34 / 40 / 35 / 41 | GPIO4..7，先由 `PINMUX` 显式交给 PWM1。 |
| TIMER1 A/B | 16..17 | 42 / 51 | GPIO8/9，PINMUX 会释放为输入；不得打开 GPIO OE 竞争。 |
| UART1 TX/RX | 18..19 | 53 / 54 | GPIO10/11，先由 `PINMUX` 显式交给 UART1。 |

以下项目**不**因 IOB 数量而自动加入 ABI：J6 的 1.8 V/显示路径、HDMI、高速差分、JTAG、
模式/配置 pin、板载 SPI Flash、PSRAM、TF、RGB/LCD 和“看起来没用的” package pin。

## 4. 交付与 HIL 放行顺序

```mermaid
flowchart LR
  A[RTL/SDK/文档] --> B[自动化仿真与 SDK 构建]
  B --> C[目标器件 P&R + manifest]
  C --> D[SRAM 下载 HIL]
  D --> E[配置 Flash 冷启动 HIL]
  E --> F[UART / User Flash A/B / 断电 HIL]
  F --> G[目标外设与电气 HIL]
  G --> H[可对外发布的板级证据]
```

目前完成到 **C**；D 至 G 必须使用实际 Tang Nano 9K、所选外设模块、当前板卡 revision 和
本次 manifest 的 `.fs` SHA-256 逐项记录。建议先完成：

1. SRAM 下载、LED、UART0、复位；
2. 配置 Flash 固化并反复断电冷启动；
3. 空白/有效/损坏 A/B 镜像、完整升级、四阶段断电；
4. GPIO 电平与高阻、I2C 上拉与真实 ACK、SPI 回环与目标设备、W5500 链路；
5. UART1、PWM1 示波器、TIMER1 编码器/滤波、RGB 共线边界；
6. 温度、电压、长线和重复擦写矩阵。

## 5. P2/P3：尚未承诺的方向

| 候选方向 | 当前结论 | 前置条件 |
| --- | --- | --- |
| 板载 SPI Flash 数据通道 | P2 可行性研究 | 不与 FPGA 配置/下载冲突的物理和软件契约、读写 HIL；不承诺 XIP。 |
| PSRAM | P2 可行性研究 | 独立时序控制器、压力测试、P&R、温度/HIL；先解决存储架构，再谈 DMA/FIFO。 |
| CAN 2.0B | P3 二选一研究 | 外置收发器、错误帧/总线 HIL、资源测量。 |
| DMA、QSPI XIP、逻辑分析仪、帧缓冲 | 不进入当前基线 | BSRAM 已为零；须先有外部存储架构与性能证据。 |
| USB FS、HDMI、RGB 帧缓冲、FPGA 以太网 MAC/PHY | 不进入 TN9K MCU 主线 | 需要独立产品、更多片上 RAM/高速 I/O 与专门 HIL。 |
| 模拟 ADC/DAC/比较器 | FPGA 无对应模拟硬件 | 使用外置器件，走当前 SPI/I2C 驱动路线。 |

## 6. 后续变更的硬门槛

任何新能力要从“研究”变为“已支持”，必须同时满足：

1. 指定 ABI 特性位、寄存器、SDK API、引脚/电压和兼容性；
2. 具备 RTL 单元测试、fabric/顶层测试、已编译固件示例与失败路径测试；
3. 更新生成规格、中文数据手册、升级/恢复文档和 SDK；
4. 用精确 `GW1NR-LV9QN88PC6/I5` 重新完成 P&R 和 packing，保留 manifest、时序、资源、warning 和位流哈希；
5. 完成相应实体板 HIL，含复位、异常、掉电、电气和目标模块；
6. 只有上述证据齐全，才可面向第三方称为“板级可用”或挂 GitHub Release。
