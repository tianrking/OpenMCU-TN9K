# OpenMCU-TN9K 工程数据手册

> 文档编号：OMCU-TN9K-DS-ZH  
> 版本：ABI <code>0x00000005</code>（主版本 0、次版本 5）  
> 目标：Tang Nano 9K，<code>GW1NR-LV9QN88PC6/I5</code> / <code>GW1N-9C</code>  
> 文档状态：工程规格，预硬件在环（pre-HIL）  
> 更新日期：2026-08-25

本文件是 OpenMCU-TN9K 的中文规格入口。寄存器数值的事实来源是
<code>spec/omcu-v0.json</code> 与自动生成的 <code>sdk/include/omcu_regs.h</code>；
CPU、存储和 I/O 的事实来源是产品顶层
<code>rtl/platform/tangnano9k/omcu_tn9k_mcu_top.sv</code> 及其依赖 RTL。

它是一份 FPGA MCU 平台数据手册，不是已经流片的半导体芯片数据手册：未实测的电压、
电流、温度、擦写寿命和 EMC 指标不会被编造为“保证值”。

![OpenMCU 产品与应用固件分层](assets/openmcu-product-flow.svg)

## 1. 先给结论：理论完整性与真实交付状态

| 问题 | 结论 |
| --- | --- |
| 在 ABI 0.5 宣称的范围内，RTL、Bootloader、SDK、镜像工具是否已经实现？ | **是**。CPU、存储、9 个 MMIO 功能块、User Flash A/B 更新路径、产品顶层和 SDK 均有实现。 |
| 是否已经过自动化数字验证？ | **是**。外设/系统/产品顶层 RTL 冒烟、SDK 构建、镜像与串口协议测试、产品 FPGA 布局布线已通过。 |
| 是否已证明每一项在实体 Tang Nano 9K 上可长期工作？ | **否**。UART/I2C/SPI/GPIO 电气、真实 User Flash 擦写、掉电恢复、配置 Flash 固化、温度/寿命仍待 HIL。 |
| 是否等于“所有常见 MCU 外设都有”？ | **否**。没有 ADC、DAC、USB、CAN、RTC、DMA、以太网、音频、低功耗控制器、硬件加密或标准 RISC-V 调试模块。 |
| 是否可称为安全量产 MCU？ | **否**。当前是 CRC32 完整性与 A/B 回退，不是签名安全启动。 |

因此正确表述是：**OpenMCU-TN9K 已是可综合、可生成产品位流、可独立更新应用的 FPGA MCU
工程基线；真板 HIL 通过前，不应宣称为已完全硬件验证或已量产。**

## 2. 产品概览

| 项目 | 当前产品模式参数 |
| --- | --- |
| CPU | PicoRV32 配置为 RV32IMC，单核、32-bit、小端、<code>ilp32</code> |
| 系统时钟 | 27 MHz 板载时钟输入；SDK 默认以此计算分频 |
| Boot ROM | 8 KiB，地址 <code>0x0000_0000</code>，FPGA 配置内固定 Bootloader |
| 总 SRAM | 44 KiB，地址 <code>0x1000_0000</code> |
| 应用运行 SRAM | 前 40 KiB，地址 <code>0x1000_0000–0x1000_9FFF</code> |
| Bootloader 工作 SRAM | 后 4 KiB，地址 <code>0x1000_A000–0x1000_AFFF</code>，应用不可使用 |
| User Flash | 76 KiB / 77,824 B，地址 <code>0x2000_0000–0x2001_2FFF</code> |
| 应用持久存储 | 2 个 36 KiB A/B 槽；每槽最大有效载荷 36,800 B |
| MMIO | 32-bit little-endian、字对齐、固定地址 ABI |
| 客户应用格式 | <code>.omcu</code>：64 B 头部 + 4 B 对齐载荷 + CRC32 |
| 客户升级接口 | UART0，3.3 V TTL，115200 / 8-N-1，停等 CRC 协议 |

~~~mermaid
flowchart TB
  subgraph FPGA[一次性固化的 FPGA MCU 平台]
    CLK[27 MHz 时钟与复位] --> CPU[PicoRV32 RV32IMC]
    CPU --> ROM[8 KiB Boot ROM]
    CPU <--> SRAM[44 KiB SRAM]
    CPU <--> MMIO[固定 MMIO ABI]
    MMIO --> P[GPIO0 / UART0 / TIMER0 / SPI0 / I2C0 / WDT0 / PWM0]
    MMIO --> IRQ[IRQCTRL + SYSCTRL]
    CPU <--> UF[76 KiB GW1NR User Flash]
  end
  subgraph App[可反复升级的客户应用]
    C[C/C++ 裸机应用] --> IMG[.omcu]
    IMG -->|UART0| BL[Bootloader]
    BL --> UF
    UF -->|校验后复制| SRAM
  end
~~~

### 2.1 FPGA 与客户 MCU 固件的边界

产品 FPGA 位流 <code>omcu_tn9k_mcu.fs</code> 只包含硬件平台和 Bootloader。客户应用
绝不重新编进 FPGA 配置；日常交付只产生 <code>.omcu</code>，写入 User Flash。

<code>OMCU_QSPI_XIP_BASE</code> 这个旧宏仍保留为兼容别名，数值同
<code>OMCU_USER_FLASH_BASE</code>；**它不表示当前产品提供 QSPI/XIP 外设。**

## 3. 验证状态与时序证据

| 层级 | 当前状态 | 证据 |
| --- | --- | --- |
| RTL 功能 | 已通过数字回归 | GPIO/UART/TIMER/SPI/I2C/WDT/PWM/IRQCTRL/SYSCTRL/User Flash、CPU 系统、SDK 程序和产品顶层都有定向测试。 |
| SDK 与工具 | 已通过 | Bootloader、示例 <code>.omcu</code>、镜像格式、串口帧协议和 Boot ROM 夹具检查均可重复构建。 |
| FPGA 实现 | 已通过 P&R | <code>omcu_tn9k_mcu_top</code> 已为 <code>GW1NR-LV9QN88PC6/I5</code> 完成综合、布局、布线与打包。 |
| 实体板 HIL | 待执行 | 真实下载、冷启动、UART、User Flash、外设波形与长期可靠性尚未记录。 |

最近一次产品 P&R 工件：

| 指标 | 结果 |
| --- | --- |
| 位流 | <code>build/tangnano9k-mcu-verify/omcu_tn9k_mcu.fs</code> |
| SHA-256 | <code>1869a8d66a11970a35602d2826a7ef0838a05498467f9d7b9a4216830927b3c2</code> |
| 时钟约束 / 实现频率 | 27.000 MHz / 40.190 MHz |
| 时序余量 | 12.155 ns |
| LUT4 / DFF / BSRAM | 6,594 / 8,640；1,758 / 6,480；26 / 26 |

40.190 MHz 是该一次工具运行的实现结果，**不是**对所有板卡、温度、电压或未来设计的
CPU 频率保证；产品当前只约束并使用 27 MHz。

## 4. CPU 与软件执行模型

### 4.1 RISC-V 配置

| 项目 | 规格 |
| --- | --- |
| 指令集 | RV32I + M + C，即 <code>rv32imc</code> |
| C ABI | <code>ilp32</code>，小端，裸机 freestanding |
| 整数寄存器 | 32 个 32-bit 通用寄存器 |
| 乘除法 | 快速乘法与除法启用 |
| 移位器 | Barrel shifter 启用 |
| 计数器 | PicoRV32 的 64-bit cycle/instruction counter 配置启用 |
| 对齐检查 | 非对齐访问和非法指令被 CPU 捕获；软件不可依赖非对齐访问成功 |
| 外部中断 | PicoRV32 自定义 IRQ ABI，固定向量，不是标准 RISC-V 特权/CSR/PLIC 模型 |

下列能力不在 ABI 0.5 承诺中：<code>A/F/D/Q/B</code>、向量、虚拟内存、特权模式、
通用 <code>Zicsr</code>、PMP、PLIC、CLINT、标准调试传输、trace、缓存一致性和 Linux。

### 4.2 复位与启动

1. 外部 <code>resetn_i</code> 低有效；顶层异步断言、同步释放。
2. CPU 从 <code>0x0000_0000</code> 的 Boot ROM 进入固定 Bootloader。
3. Bootloader 扫描 A/B 槽，选择序号最新、已提交、ABI/头部/载荷 CRC 均合法的镜像。
4. 若存在有效镜像，Bootloader 在 UART0 等待连接约 750 ms；未连接时将应用复制到 SRAM，
   再跳转 <code>0x1000_0000</code>。
5. 若没有有效镜像，Bootloader 持续监听 UART0，直到写入一个合格镜像。

当前版本没有应用软件主动请求跳回 Bootloader 的公开命令；恢复方式是“先启动 PC 下载器，
再按复位”。应用与 Bootloader 会在不同时间占用同一个 UART0。

## 5. 存储器与镜像格式

### 5.1 CPU 地址图

| 地址范围 | 大小 / 可用范围 | 用途 | 应用可否直接使用 |
| --- | ---: | --- | --- |
| <code>0x0000_0000–0x0000_1FFF</code> | 8 KiB | FPGA 内 Boot ROM | 否；固定 Bootloader |
| <code>0x1000_0000–0x1000_9FFF</code> | 40 KiB | 客户应用代码、数据、栈和 IRQ frame | 是 |
| <code>0x1000_A000–0x1000_AFFF</code> | 4 KiB | Bootloader 临时工作区 | 否 |
| <code>0x2000_0000–0x2000_8FFF</code> | 36 KiB | User Flash 槽 A | 否；Bootloader 管理 |
| <code>0x2000_9000–0x2001_1FFF</code> | 36 KiB | User Flash 槽 B | 否；Bootloader 管理 |
| <code>0x2001_2000–0x2001_2FFF</code> | 4 KiB | User Flash 保留页 | 否 |
| <code>0x4000_0000–0x4000_FFFF</code> | 固定 MMIO aperture | 下方外设寄存器 | 按公开 ABI 使用 |

User Flash 的物理页大小为 2 KiB，共 38 页。槽 A/B 各占 18 页，最后两页保留。
应用镜像头为 64 B，载荷按 4 B 对齐，因此单槽载荷上限为
<code>36,864 - 64 = 36,800 B</code>。

### 5.2 User Flash 原始访问边界

User Flash 控制器把物理 <code>FLASH608K</code> 映射为字节地址窗口。控制器在硬件层支持：

| 操作 | 总线形式 | 语义 |
| --- | --- | --- |
| 读取 | 读事务 | 返回 32-bit Flash word |
| 编程 | 4 字节写使能、32-bit 对齐 | 编程一个 word；Flash 只能从 1 写为 0 |
| 擦除 | 仅低字节写使能 | 擦除目标地址所在的 2 KiB 页 |

这是 Bootloader 的底层能力，不是客户应用配置存储 API。应用自行擦写会破坏 A/B 槽、
镜像 CRC 和掉电回退语义；客户更新必须使用 <code>tools/omcu_flash.py</code>。

### 5.3 <code>.omcu</code> 头部

| 字段 | 宽度 | 含义 |
| --- | ---: | --- |
| <code>magic</code> | 32 bit | <code>0x4F4D4355</code>，ASCII “OMCU” |
| <code>format_version</code> | 16 bit | 当前为 1 |
| <code>header_bytes</code> | 16 bit | 固定 64 |
| <code>hardware_abi</code> | 32 bit | 必须为 <code>0x00000005</code> |
| <code>load_address</code> | 32 bit | 固定 <code>0x10000000</code> |
| <code>entry_address</code> | 32 bit | 固定 <code>0x10000000</code> |
| <code>payload_bytes</code> | 32 bit | 4 B 对齐、非零、最大 36,800 |
| <code>payload_crc32</code> | 32 bit | 载荷 CRC32 |
| <code>sequence</code> | 32 bit | A/B 选择时使用的递增序号 |
| <code>state</code> | 32 bit | 擦除 <code>FFFFFFFF</code>、暂存 <code>FFFFFFFE</code>、已提交 <code>FFFFFFFC</code> |
| <code>header_crc32</code> | 32 bit | 状态字段与自身置零后的头部 CRC32 |
| <code>reserved[6]</code> | 192 bit | 必须保留 |

最终提交仅将状态字从 <code>STAGING</code> 清位为 <code>COMMITTED</code>。因此擦除、
传输或校验期间掉电不会让半写入镜像取代旧的已提交槽。

## 6. 引脚、时钟和电气边界

所有下列 package pad 已经通过产品 P&R 解析，但尚未替代实体板测量。I/O 约束为
<code>LVCMOS33</code>；不要接 5 V 信号。

| 功能 | 顶层信号 / GPIO 位 | package pad | 电气与使用限制 |
| --- | --- | ---: | --- |
| 系统时钟 | <code>clk_27m_i</code> | 52 | 板载 27 MHz；不承诺外部时钟切换。 |
| 复位 | <code>resetn_i</code> | 4 | 低有效；应保留为救砖入口。 |
| UART0 TX / RX | <code>uart_tx_o</code> / <code>uart_rx_i</code> | 17 / 18 | 3.3 V TTL，115200 / 8-N-1 约定；TX/RX 交叉、共地。 |
| LED0–5 | GPIO0[0:5] | 10, 11, 13, 14, 15, 16 | 板载低有效 LED；不是公开外接 GPIO。 |
| SPI0 | CS/MOSI/SCK/MISO | 38 / 37 / 36 / 39 | 与 J5/TF 信号组共享；不要同时使用 microSD。 |
| I2C0 | SCL / SDA | 26 / 27 | 真正开漏；必须外部上拉到 3.3 V。 |
| PWM0 | <code>pwm0_o</code> | 25 | 单通道。 |
| GPIO0–2 | GPIO0[6:8] | 28 / 29 / 30 | 可输入、输出或高阻；复位为高阻。 |

I2C 外部上拉建议 2.2 kΩ–10 kΩ（常见 4.7 kΩ），并以实际总线电容和速度复核。
GPIO 输入没有高速采样、专用同步器或过压保护承诺；异步/高速信号需要外部或新增 RTL 处理。

## 7. 外设总表

| 外设 | 基址 | 数量 | 已实现能力 | 明确不提供 |
| --- | --- | ---: | --- | --- |
| GPIO0 | <code>0x4000_0000</code> | 9 bit | 输出锁存、OE、高阻、输入、升/降沿 sticky IRQ | ADC、去抖、高速捕获、复用器 |
| UART0 | <code>0x4000_1000</code> | 1 | 8-N-1、可编程分频、TX/RX、RX IRQ、溢出/帧错状态 | FIFO、流控、DMA、RS-485 自动方向 |
| TIMER0 | <code>0x4000_2000</code> | 1 | 32-bit 比较、16-bit 分频、单次/自动重装、IRQ | capture、多个 compare、RTC 时钟 |
| SPI0 | <code>0x4000_3000</code> | 1 | 8-bit、MSB first、Mode 0、单 CS、完成 IRQ | 多 CS、FIFO、DMA、Mode 1/2/3、QSPI/XIP |
| I2C0 | <code>0x4000_4000</code> | 1 | 单主机、字节命令、START/repeated START/STOP、读写、时钟拉伸、完成 IRQ | 多主仲裁恢复、FIFO、DMA、总线恢复、自动超时 |
| WDT0 | <code>0x4000_5000</code> | 1 | 32-bit 计数、喂狗、过期 IRQ、请求全 SoC 复位 | 独立低速时钟、窗口看门狗 |
| PWM0 | <code>0x4000_6000</code> | 1 | 单路边沿对齐、分频、周期、占空比、反相 | 多通道、互补输出、死区、捕获 |
| IRQCTRL | <code>0x4000_7000</code> | 6 源 | sticky 捕获、屏蔽、软件强制、固定优先级 | PLIC、嵌套优先级、标准 CSR 中断 |
| SYSCTRL | <code>0x4000_F000</code> | 1 | 芯片 ID、ABI、功能位、build ID、ROM/SRAM 容量 | 复位原因、温度、电源、调试控制 |
| User Flash | <code>0x2000_0000</code> | 76 KiB | Bootloader A/B 镜像存储 | 应用文件系统、XIP、应用直接管理 API |

## 8. 通用 MMIO 规则

- 所有公开寄存器宽度为 32 bit little-endian，按 4 B 对齐。
- <code>RO</code> 为只读，<code>RW</code> 为读写，<code>WO</code> 为只写，
  <code>W1C</code> 表示“写 1 清除”，写 0 无影响。
- 未列出的位为保留位：软件读取时忽略，写入时应写 0。
- 外设寄存器复位值仅适用于 SoC 复位后；外部输入、I2C 总线电平和 GPIO 输入值由板级电路决定。
- 应用启动时应读取 <code>SYSCTRL.CHIP_ID</code>、ABI 主版本和功能位，不能仅靠位流文件名判断硬件。

## 9. 完整寄存器参考

### 9.1 GPIO0：<code>0x4000_0000</code>

当前 Tang 产品实现宽度为 bit[8:0]。bit[5:0] 为 LED，bit[8:6] 为外接 GPIO。

| 偏移 | 名称 | 访问 | 复位 | 位定义 |
| ---: | --- | --- | --- | --- |
| 0x00 | OUT | RW | 0 | [8:0] 输出锁存 |
| 0x04 | OUT_SET | WO | — | 写 1 置对应 OUT bit |
| 0x08 | OUT_CLR | WO | — | 写 1 清对应 OUT bit |
| 0x0C | OUT_XOR | WO | — | 写 1 翻转对应 OUT bit |
| 0x10 | OE | RW | 0 | [8:0] 输出使能；0 为高阻/输入 |
| 0x14 | OE_SET | WO | — | 写 1 使能输出 |
| 0x18 | OE_CLR | WO | — | 写 1 释放输出 |
| 0x20 | IN | RO | 外部决定 | [8:0] 输入采样 |
| 0x24 | RISE_EN | RW | 0 | [8:0] 上升沿 IRQ 使能 |
| 0x28 | FALL_EN | RW | 0 | [8:0] 下降沿 IRQ 使能 |
| 0x2C | IRQ_STATUS | W1C / 读 | 0 | [8:0] sticky 边沿状态，写 1 清除 |

GPIO 事件应先处理/清除 <code>IRQ_STATUS</code>，再清 IRQCTRL 的 bit 8。

### 9.2 UART0：<code>0x4000_1000</code>

UART 固定为 8 data bits、无校验、1 stop bit。分频值为“每 bit 时钟数减一”：
<code>baud ≈ 27,000,000 / (BAUDDIV + 1)</code>。复位值 233 约为 115,385 baud。

| 偏移 | 名称 | 访问 | 复位 | 位定义 |
| ---: | --- | --- | --- | --- |
| 0x00 | DATA | RW | 0 | 写 [7:0] 发送一字节；读 [7:0] 取 RX 字节并消耗 RX_VALID |
| 0x04 | STATUS | RO + W1C | 0 | bit0 TX_READY；bit1 RX_VALID；bit2 RX_OVERRUN (W1C)；bit3 RX_FRAMING_ERROR (W1C)；bit4 TX_BUSY |
| 0x08 | BAUDDIV | RW | 233 | [15:0] 每 bit 时钟数减一 |
| 0x0C | CTRL | RW | 0 | bit0 TX_ENABLE；bit1 RX_ENABLE；bit2 RX_IRQ_ENABLE |

只有 RX_VALID 与 RX_IRQ_ENABLE 同时为 1 才会产生 IRQCTRL bit 9。没有 RX FIFO：
未读数据到来会置 RX_OVERRUN。

### 9.3 TIMER0：<code>0x4000_2000</code>

计数 tick 周期为 <code>(PRESCALE + 1) / 27 MHz</code>。当 COUNT 与 COMPARE 相等，
置 PENDING；非自动重装模式会停止。

| 偏移 | 名称 | 访问 | 复位 | 位定义 |
| ---: | --- | --- | --- | --- |
| 0x00 | CTRL | RW | 0 | bit0 ENABLE；bit1 IRQ_ENABLE；bit2 AUTO_RELOAD |
| 0x04 | PRESCALE | RW | 0 | [15:0] tick 分频减一 |
| 0x08 | COUNT | RW | 0 | 当前计数 |
| 0x0C | COMPARE | RW | FFFFFFFF | 比较值 |
| 0x10 | STATUS | W1C / 读 | 0 | bit0 PENDING |

### 9.4 SPI0：<code>0x4000_3000</code>

SPI0 为单主机、8-bit、MSB first、CPOL=0/CPHA=0（Mode 0）。每次 START 自动拉低唯一
的低有效 CS，完成一个字节后释放。无时钟拉伸与 FIFO。

<code>fSCK = 27 MHz / (2 × (CLKDIV + 1))</code>；复位 CLKDIV=134 时约为 100 kHz。

| 偏移 | 名称 | 访问 | 复位 | 位定义 |
| ---: | --- | --- | --- | --- |
| 0x00 | DATA | RW | 0 | 写 [7:0] 为 TX；读 [7:0] 为完成的 RX |
| 0x04 | STATUS | RO + W1C | 0 | bit0 BUSY；bit1 DONE (W1C) |
| 0x08 | CLKDIV | RW | 134 | [15:0] SCK 半周期时钟数减一 |
| 0x0C | CTRL | RW | 0 | bit0 ENABLE；bit1 DONE_IRQ_ENABLE |
| 0x10 | START | WO | — | bit0=1 时，在 ENABLE 且非 BUSY 条件下开始一字节传输 |

SPI 完成 IRQ 映射到 IRQCTRL bit 11。

### 9.5 I2C0：<code>0x4000_4000</code>

I2C0 为单主机开漏逐字节引擎。无时钟拉伸时，
<code>fSCL ≈ 27 MHz / (2 × (CLKDIV + 1))</code>；复位 CLKDIV=134 约为 100 kHz。
目标拉低 SCL 时控制器等待，因而支持目标 clock stretching。

| 偏移 | 名称 | 访问 | 复位 | 位定义 |
| ---: | --- | --- | --- | --- |
| 0x00 | DATA | RW | 0 | 写 [7:0] 为 TX；读 [7:0] 为 RX |
| 0x04 | STATUS | RO + W1C | 0 | bit0 BUSY；bit1 DONE；bit2 ACK_ERROR；bit3 COMMAND_ERROR；bit4 BUS_ACTIVE |
| 0x08 | CLKDIV | RW | 134 | [15:0] SCL 相位时钟数减一 |
| 0x0C | CTRL | RW | 0 | bit0 ENABLE；bit1 DONE_IRQ_ENABLE |
| 0x10 | CMD | WO | — | 恰好写一个命令 bit：bit0 START、bit1 STOP、bit2 WRITE、bit3 READ_ACK、bit4 READ_NACK |

命令序列由软件组织；重复 START 合法。WRITE/READ/STOP 必须发生在已 START 的事务中。
禁用 CTRL 会释放两根线并放弃当前事务。完成/错误 IRQ 映射到 IRQCTRL bit 12。

### 9.6 WDT0：<code>0x4000_5000</code>

WDT0 使用 SoC 27 MHz 时钟，不是独立低速看门狗。到达阈值后可置过期 IRQ，并向顶层发出
一个复位请求脉冲；顶层把该脉冲扩展为 MCU 复位。

| 偏移 | 名称 | 访问 | 复位 | 位定义 |
| ---: | --- | --- | --- | --- |
| 0x00 | CTRL | RW | 0 | bit0 ENABLE；bit1 RESET_ENABLE；bit2 IRQ_ENABLE |
| 0x04 | TIMEOUT | RW | FFFFFFFF | 32-bit 过期计数阈值 |
| 0x08 | FEED | WO | — | 写 <code>0x51F15EED</code> 清计数并清 EXPIRED |
| 0x0C | STATUS | RO + W1C | 0 | bit0 EXPIRED (W1C)；bit1 RESET_REQUEST（当前脉冲） |

约略超时为 <code>(TIMEOUT + 1) / 27 MHz</code>。WDT0 IRQ 映射到 IRQCTRL bit 13。

### 9.7 PWM0：<code>0x4000_6000</code>

PWM0 是一条边沿对齐输出。输出在 <code>COUNT &lt; DUTY</code> 时为高；若启用 INVERT，
最终输出极性反相。

<code>fPWM = 27 MHz / ((PRESCALE + 1) × (PERIOD + 1))</code>。

| 偏移 | 名称 | 访问 | 复位 | 位定义 |
| ---: | --- | --- | --- | --- |
| 0x00 | CTRL | RW | 0 | bit0 ENABLE；bit1 INVERT |
| 0x04 | PRESCALE | RW | 0 | [15:0] PWM tick 分频减一 |
| 0x08 | PERIOD | RW | 0000FFFF | 包含端点的计数 top |
| 0x0C | DUTY | RW | 0 | 高电平计数阈值 |
| 0x10 | COUNT | RO | 0 | 当前 PWM 计数 |

### 9.8 IRQCTRL：<code>0x4000_7000</code>

IRQCTRL 不是 PLIC。它以 PicoRV32 IRQ 位号保存 6 路 sticky pending，并以最小位号为
固定最高优先级。

| 偏移 | 名称 | 访问 | 复位 | 位定义 |
| ---: | --- | --- | --- | --- |
| 0x00 | PENDING | RO | 0 | 当前/锁存来源 mask，位位置即 CPU IRQ 位 |
| 0x04 | ENABLE | RW | 0 | 对应来源投递使能 mask |
| 0x08 | CLEAR | WO | — | 写 1 清 sticky 与 FORCE 来源；同周期真实事件优先 |
| 0x0C | FORCE | WO | — | 写 1 置软件 pending 来源 |
| 0x10 | ACTIVE | RO | 0 | <code>PENDING &amp; ENABLE</code>，送到 CPU 的 mask |
| 0x14 | HIGHEST | RO | 0 | 最小编号 active CPU IRQ 位；无 active 时为 0 |

| CPU IRQ bit | SDK 常量 | 来源 |
| ---: | --- | --- |
| 8 | OMCU_IRQ_GPIO0 | GPIO0 edge status |
| 9 | OMCU_IRQ_UART0 | UART0 RX valid |
| 10 | OMCU_IRQ_TIMER0 | TIMER0 pending |
| 11 | OMCU_IRQ_SPI0 | SPI0 done |
| 12 | OMCU_IRQ_I2C0 | I2C0 command terminal result |
| 13 | OMCU_IRQ_WDT0 | WDT0 expiry |

应用必须先清除外设源状态，再向 CLEAR 写对应 bit；反过来会让仍有效的来源再次被捕获。
SDK 固定在应用 SRAM 的 IRQ 向量 <code>0x1000_0010</code> 执行现场保护与分发；
应用只应覆盖 <code>omcu_irq_dispatch()</code>，不要自行发射 PicoRV32 自定义 IRQ 指令。

### 9.9 SYSCTRL：<code>0x4000_F000</code>

| 偏移 | 名称 | 访问 | 当前产品读值 / 定义 |
| ---: | --- | --- | --- |
| 0x00 | CHIP_ID | RO | <code>0x4F4D4355</code>（ASCII OMCU） |
| 0x04 | ABI | RO | <code>0x00000005</code>：major [31:16]，minor [15:0] |
| 0x08 | FEATURES | RO | 当前产品为 <code>0x000040FF</code> |
| 0x0C | BUILD_ID | RO | 当前 RTL 参数为 <code>0x00000001</code>；不是加密版本标识 |
| 0x10 | MEMORY_KIB | RO | 当前产品为 <code>0x002C0008</code>：SRAM 44 KiB、ROM 8 KiB |

FEATURES 位定义：

| bit | SDK 常量 | 功能 |
| ---: | --- | --- |
| 0 | OMCU_FEATURE_GPIO0 | GPIO0 |
| 1 | OMCU_FEATURE_UART0 | UART0 |
| 2 | OMCU_FEATURE_TIMER0 | TIMER0 |
| 3 | OMCU_FEATURE_SPI0 | SPI0 |
| 4 | OMCU_FEATURE_I2C0 | I2C0 |
| 5 | OMCU_FEATURE_WDT0 | WDT0 |
| 6 | OMCU_FEATURE_PWM0 | PWM0 |
| 7 | OMCU_FEATURE_IRQCTRL | IRQCTRL |
| 14 | OMCU_FEATURE_USER_FLASH | User Flash |

## 10. UART Bootloader 与客户升级接口

### 10.1 物理与所有权

UART0 在复位后先属于 Bootloader，约 750 ms 后若未连接则属于应用。应用运行期可以用
同一 UART 做日志或业务协议；升级时“先启动主机工具，再复位”即可让 Bootloader 重获
控制权。必须保留 TX、RX、GND 与复位入口，且外部业务设备在复位时不能争用信号。

### 10.2 帧协议摘要

| 项目 | 值 |
| --- | --- |
| 起始字节 | <code>A5 5A</code> |
| 字段顺序 | type（8 bit）、sequence（LE16）、length（LE16）、payload、CRC32（LE32） |
| 最大 payload | 128 B |
| 单个 DATA 载荷 | 最多 124 B（前 4 B 为 offset） |
| 主机命令 | HELLO=1、BEGIN=2、DATA=3、END=4、BOOT=5 |
| 设备响应 | HELLO=0x81、ACK=0x82、NACK=0x83 |
| 可靠性 | 停等、序号、帧 CRC32、主机重试；重复 DATA / END 幂等 |

完整命令载荷、NACK 错误码、恢复流程和 Windows 命令见
[独立 MCU 固件开发与升级](mcu-firmware-update.md)。

## 11. SDK 与客户开发合同

客户程序以 <code>omcu_add_application()</code> 构建，链接到前 40 KiB SRAM，输出
<code>.elf</code>、<code>.bin</code> 与 <code>.omcu</code>。不要使用旧
<code>omcu_add_firmware()</code> 的 <code>.hex</code> 作为客户升级包。

~~~cmake
omcu_add_application(omcu_my_product examples/my_product/main.c)
~~~

~~~powershell
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
python .\tools\omcu_image.py validate --image .\build\sdk\omcu_my_product.omcu
python .\tools\omcu_flash.py --port COM5 --image .\build\sdk\omcu_my_product.omcu
~~~

公开 C API 位于 <code>sdk/include/omcu.h</code>，板级 GPIO/时钟定义位于
<code>sdk/include/omcu_tn9k.h</code>。应用不应直接依赖 PicoRV32 源码、内部 MMIO
fabric、User Flash 原始擦写流程或 FPGA package pin 编号。

## 12. 当前不提供的能力

下表是产品边界，不是未来承诺；需要这些能力时，必须新增 RTL、ABI/feature bit、SDK、
测试、P&R 和 HIL，不能仅在应用 C 代码中“假设存在”。

| 类别 | ABI 0.5 不提供 |
| --- | --- |
| 模拟与高速采集 | ADC、DAC、比较器、运放、温度传感器、高速 GPIO capture |
| 通信 | USB、CAN/CAN-FD、以太网、BLE/Wi-Fi、UART1、SPI 多 CS/QSPI、I2S |
| 存储 | 应用文件系统、EEPROM 模拟、PSRAM 驱动、板载 SPI Flash XIP |
| 处理与调试 | DMA、缓存、MPU/PMP、标准 RISC-V debug/CSR/PLIC/CLINT、trace |
| 低功耗与时钟 | RTC、独立低速时钟、睡眠/唤醒、DVFS、BOR |
| 安全 | 镜像签名、密钥存储、反回滚、调试锁定、加密引擎 |
| 可靠性证明 | 电气绝对最大值、功耗、温度等级、EMC、Flash 擦写寿命、真板长期测试 |

## 13. 发布和 HIL 门槛

在给客户“可正常 MCU 升级”的交付物前，至少验证：

1. 产品 <code>.fs</code> 的 SRAM 下载、非易失配置写入、10 次以上断电冷启动；
2. 空白 User Flash 首装、A/B 连续升级、错误 ABI/CRC 拒绝、重复帧和主机重连；
3. 擦除、数据写入、END 校验、最终 COMMITTED 四阶段的断电恢复；
4. UART0、GPIO、PWM、SPI、I2C、WDT、IRQ 的实际板级波形与外部目标行为；
5. 电压、温度、连接器、信号完整性与反复更新寿命；
6. 若暴露给不可信环境，再完成签名安全启动、密钥和调试口安全设计。

详细的验证证据、已知工具 warning 与发布卫生见
[验证状态与发布门槛](validation-and-release.md)。

## 14. 相关文档

- [中文开发总览](README.md)
- [构建与烧录](build-and-program.md)
- [硬件与引脚](hardware-and-pins.md)
- [外设与 SDK](peripherals-and-sdk.md)
- [中断开发约定](interrupts.md)
- [独立 MCU 固件开发与升级](mcu-firmware-update.md)
- [测试计划](../../tests/README.md)

## 15. 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| ABI 0.5 / pre-HIL | 2026-08-25 | 首次发布中文工程数据手册：统一产品存储、引脚、全部寄存器、升级协议、能力边界和验证状态。 |
