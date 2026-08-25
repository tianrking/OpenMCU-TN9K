# OpenMCU ABI 0.5 寄存器参考

所有 v0 MMIO 寄存器均为 32 位、小端、按字对齐；地址在 ABI 主版本 0 内保持稳定。ABI 次版本 5 保留 IRQCTRL 和已文档化的 PicoRV32 自定义 IRQ SDK 路径，并为 Tang Nano 9K 产品模式加入 User Flash 特性位。已审阅的机器可读寄存器来源是 <a href="../spec/omcu-v0.json">spec/omcu-v0.json</a>，C 寄存器头文件从该来源生成。包含 User Flash、复位值和引脚绑定的完整中文产品规范见 <a href="zh-CN/datasheet.md">工程数据手册</a>。

## GPIO0 — <code>0x4000_0000</code>

所有 GPIO 位字段均作用于已实现的 GPIO 宽度。当前 Tang Nano 9K 目标使用位 <code>0:5</code> 驱动低有效 LED，位 <code>6:8</code> 暴露为三个真实的扩展 GPIO Pad。已审阅的约束映射和电气限制见 <a href="zh-CN/hardware-and-pins.md">硬件与引脚</a>。

| 偏移 | 寄存器 | 访问 | 含义 |
| --- | --- | --- | --- |
| <code>0x00</code> | <code>OUT</code> | RW | 输出锁存器 |
| <code>0x04</code> | <code>OUT_SET</code> | WO | 写 1 置位对应输出位 |
| <code>0x08</code> | <code>OUT_CLR</code> | WO | 写 1 清除对应输出位 |
| <code>0x0C</code> | <code>OUT_XOR</code> | WO | 写 1 翻转对应输出位 |
| <code>0x10</code> | <code>OE</code> | RW | 输出使能锁存器 |
| <code>0x14</code> | <code>OE_SET</code> | WO | 写 1 使能对应输出位 |
| <code>0x18</code> | <code>OE_CLR</code> | WO | 写 1 禁用对应输出位 |
| <code>0x20</code> | <code>IN</code> | RO | 输入采样；外部异步输入需要平台同步器 |
| <code>0x24</code> | <code>RISE_EN</code> | RW | 上升沿中断使能位 |
| <code>0x28</code> | <code>FALL_EN</code> | RW | 下降沿中断使能位 |
| <code>0x2C</code> | <code>IRQ_STATUS</code> | RW1C | 锁存的边沿标志；写 1 清除 |

## UART0 — <code>0x4000_1000</code>

UART0 使用 8-N-1。<code>BAUDDIV</code> 的值是每位的系统时钟周期数减 1；27 MHz 系统时钟下使用 <code>233</code> 可得到约 115200 baud。

| 偏移 | 寄存器 | 访问 | 含义 |
| --- | --- | --- | --- |
| <code>0x00</code> | <code>DATA</code> | RW | 位 <code>7:0</code>：写入时为 TX 字节，读取时为 RX 字节；读取会消费 <code>RX_VALID</code>。 |
| <code>0x04</code> | <code>STATUS</code> | RW | 位 0 <code>TX_READY</code>，位 1 <code>RX_VALID</code>，位 2 <code>RX_OVERRUN</code>（W1C），位 3 <code>RX_FRAMING_ERROR</code>（W1C），位 4 <code>TX_BUSY</code>。 |
| <code>0x08</code> | <code>BAUDDIV</code> | RW | 位 <code>15:0</code>：每位周期数减 1；复位值 <code>233</code>。 |
| <code>0x0C</code> | <code>CTRL</code> | RW | 位 0 <code>TX_ENABLE</code>，位 1 <code>RX_ENABLE</code>，位 2 <code>RX_IRQ_ENABLE</code>。 |

当 <code>RX_VALID</code> 和 <code>RX_IRQ_ENABLE</code> 均为 1 时，<code>irq_o</code> 有效。中断式 UART 接收器应先读取 <code>DATA</code>，再通过 IRQCTRL 确认 <code>OMCU_IRQ_UART0</code>；详见 <a href="interrupts.md">中断约定</a>。

## TIMER0 — <code>0x4000_2000</code>

| 偏移 | 寄存器 | 访问 | 含义 |
| --- | --- | --- | --- |
| <code>0x00</code> | <code>CTRL</code> | RW | 位 0 <code>ENABLE</code>，位 1 <code>IRQ_ENABLE</code>，位 2 <code>AUTO_RELOAD</code>。 |
| <code>0x04</code> | <code>PRESCALE</code> | RW | 位 <code>15:0</code>：每个计数所含时钟数减 1。 |
| <code>0x08</code> | <code>COUNT</code> | RW | 当前计数值。 |
| <code>0x0C</code> | <code>COMPARE</code> | RW | 比较计数值。 |
| <code>0x10</code> | <code>STATUS</code> | RW1C | 位 0 <code>PENDING</code>；写 1 清除。 |

非自动重装定时器到达比较值时停止；自动重装定时器回到零并继续计数。

## SPI0 — <code>0x4000_3000</code>

SPI0 是紧凑的 8 位、MSB 优先、CPOL=0/CPHA=0（mode 0）主机。一次 <code>START</code> 操作会自动拉低一个低有效片选，并恰好完成一个字节传输。未来的 QSPI/XIP 或 DMA 控制器必须作为新 ABI 模块单独文档化。

| 偏移 | 寄存器 | 访问 | 含义 |
| --- | --- | --- | --- |
| <code>0x00</code> | <code>DATA</code> | RW | 写入下一个 TX 字节；读取完成的 RX 字节。 |
| <code>0x04</code> | <code>STATUS</code> | RW1C | 位 0 <code>BUSY</code>；位 1 <code>DONE</code>，写 1 清除。 |
| <code>0x08</code> | <code>CLKDIV</code> | RW | 位 <code>15:0</code>：每个 SCK 半周期的系统时钟数减 1。 |
| <code>0x0C</code> | <code>CTRL</code> | RW | 位 0 <code>ENABLE</code>；位 1 <code>DONE_IRQ_ENABLE</code>。 |
| <code>0x10</code> | <code>START</code> | WO | 位 0 在 <code>ENABLE=1</code> 且 <code>BUSY=0</code> 时启动传输。 |

## I2C0 — <code>0x4000_4000</code>

I2C0 是开漏、单主机、按字节工作的引擎。<code>SCL</code> 与 <code>SDA</code> 输出通知平台何时应把线路拉低；平台必须提供上拉、开漏 Pad 和同步后的线路输入。每次 <code>CMD</code> 写入只发起一个操作，软件可显式组合地址、写、重复 START 和读事务。控制器在释放 SCL 时遵守目标时钟拉伸。

它刻意没有 FIFO、DMA、仲裁丢失处理、总线恢复序列或自动超时；如果目标永久占用总线，产品应用应通过看门狗或外层超时策略处理。

| 偏移 | 寄存器 | 访问 | 含义 |
| --- | --- | --- | --- |
| <code>0x00</code> | <code>DATA</code> | RW | 写入下一个 TX 字节；读取完成的 RX 字节。 |
| <code>0x04</code> | <code>STATUS</code> | RW1C | 位 0 <code>BUSY</code>；位 1 <code>DONE</code>（W1C）；位 2 <code>ACK_ERROR</code>（W1C，<code>WRITE</code> 后目标 NACK）；位 3 <code>COMMAND_ERROR</code>（W1C）；位 4 <code>BUS_ACTIVE</code>（RO）。 |
| <code>0x08</code> | <code>CLKDIV</code> | RW | 位 <code>15:0</code>：SCL 高/低相位的系统时钟数减 1；复位值 <code>134</code>，27 MHz 且无拉伸时约为 100 kHz。 |
| <code>0x0C</code> | <code>CTRL</code> | RW | 位 0 <code>ENABLE</code>；位 1 <code>DONE_IRQ_ENABLE</code>。禁用会释放两根线并放弃活动事务。 |
| <code>0x10</code> | <code>CMD</code> | WO | 只能写位 0 <code>START</code>、1 <code>STOP</code>、2 <code>WRITE</code>、3 <code>READ_ACK</code>、4 <code>READ_NACK</code> 之一。<code>WRITE</code>/<code>READ_*</code>/<code>STOP</code> 需要此前的 START；第二次 START 是重复 START。 |

命令达到终止结果时会置 <code>DONE</code>，包括立即被拒绝的命令。非法或越序命令置 <code>COMMAND_ERROR</code>；字节写 ACK 时目标保持 SDA 高会置 <code>ACK_ERROR</code>。<code>BUS_ACTIVE</code> 为 1 时，控制器在命令之间保持 SCL 低，避免软件准备下一字节时意外产生 STOP。

## WDT0 — <code>0x4000_5000</code>

看门狗以 SoC 时钟运行。到期时锁存 <code>EXPIRED</code>，可产生 IRQ，也可向平台复位序列器发出一个周期的复位请求。Tang bring-up 封装会把该请求拉伸为标准 MCU 复位；软件应写入已文档化的魔数喂狗，而不是写计数器。

| 偏移 | 寄存器 | 访问 | 含义 |
| --- | --- | --- | --- |
| <code>0x00</code> | <code>CTRL</code> | RW | 位 0 <code>ENABLE</code>，位 1 <code>RESET_ENABLE</code>，位 2 <code>IRQ_ENABLE</code>。 |
| <code>0x04</code> | <code>TIMEOUT</code> | RW | 运行计数到达此值时到期。 |
| <code>0x08</code> | <code>FEED</code> | WO | 写入 <code>0x51F15EED</code> 重新开始计数。 |
| <code>0x0C</code> | <code>STATUS</code> | RW1C | 位 0 <code>EXPIRED</code>；位 1 是有效的 <code>RESET_REQUEST</code> 脉冲。 |

## PWM0 — <code>0x4000_6000</code>

PWM0 提供一路边沿对齐输出。<code>COUNT &lt; DUTY</code> 时输出高电平；<code>PERIOD</code> 是包含式顶值，所以一个完整周期包含 <code>PERIOD + 1</code> 个计数 tick。Tang Nano 9K 封装将其绑定到一个已审阅的封装 Pad；其他平台必须显式完成自己的 Pad 绑定。

| 偏移 | 寄存器 | 访问 | 含义 |
| --- | --- | --- | --- |
| <code>0x00</code> | <code>CTRL</code> | RW | 位 0 <code>ENABLE</code>；位 1 <code>INVERT</code>。 |
| <code>0x04</code> | <code>PRESCALE</code> | RW | 位 <code>15:0</code>：每个 PWM tick 的系统时钟数减 1。 |
| <code>0x08</code> | <code>PERIOD</code> | RW | 包含式计数顶值。 |
| <code>0x0C</code> | <code>DUTY</code> | RW | 高电平计数上限。 |
| <code>0x10</code> | <code>COUNT</code> | RO | 当前 PWM 计数器。 |

## IRQCTRL — <code>0x4000_7000</code>

IRQCTRL 将可移植外设事件线转换为六个稳定 CPU 位位置，在软件屏蔽时仍捕获短事件，并提供软件投递策略。它不是标准 RISC-V PLIC。C 处理器、固定向量和自定义 CPU 掩码接口见 <a href="interrupts.md">中断约定</a>。

| 偏移 | 寄存器 | 访问 | 含义 |
| --- | --- | --- | --- |
| <code>0x00</code> | <code>PENDING</code> | RO | 处于 CPU IRQ 位位置的锁存/当前源掩码。 |
| <code>0x04</code> | <code>ENABLE</code> | RW | 处于 CPU IRQ 位位置的逐源投递使能掩码。 |
| <code>0x08</code> | <code>CLEAR</code> | WO | 写 1 清除锁存和软件强制源位；若当前源与清除同时发生，当前源优先。 |
| <code>0x0C</code> | <code>FORCE</code> | WO | 写 1 置位一个软件待处理中断源。 |
| <code>0x10</code> | <code>ACTIVE</code> | RO | <code>PENDING &amp; ENABLE</code>，会投递到 CPU。 |
| <code>0x14</code> | <code>HIGHEST</code> | RO | 编号最小的活动 CPU IRQ 位；无活动源时为零。 |

| CPU 位 | SDK 常量 | 来源 |
| --- | --- | --- |
| 8 | <code>OMCU_IRQ_GPIO0</code> | GPIO0 边沿状态事件 |
| 9 | <code>OMCU_IRQ_UART0</code> | UART0 RX 有效 |
| 10 | <code>OMCU_IRQ_TIMER0</code> | TIMER0 待处理 |
| 11 | <code>OMCU_IRQ_SPI0</code> | SPI0 完成 |
| 12 | <code>OMCU_IRQ_I2C0</code> | I2C0 终止命令结果 |
| 13 | <code>OMCU_IRQ_WDT0</code> | WDT0 到期 |

<code>PENDING</code> 与 <code>ENABLE</code> 使用 CPU 位位置而不是紧凑源索引。<code>OMCU_IRQ_EXTERNAL_MASK</code> 为 <code>0x0000_3F00</code>。软件必须先清除外设的起始条件，再向 <code>CLEAR</code> 写入对应位，否则仍有效的电平式源会按设计再次被捕获。

## SYSCTRL — <code>0x4000_F000</code>

| 偏移 | 寄存器 | 访问 | 含义 |
| --- | --- | --- | --- |
| <code>0x00</code> | <code>CHIP_ID</code> | RO | <code>0x4F4D4355</code>（<code>OMCU</code>） |
| <code>0x04</code> | <code>ABI</code> | RO | 位 <code>31:16</code> 为 ABI 主版本，位 <code>15:0</code> 为次版本（<code>0.5</code>） |
| <code>0x08</code> | <code>FEATURES</code> | RO | 位 0..7：GPIO0/UART0/TIMER0/SPI0/I2C0/WDT0/PWM0/IRQCTRL；位 14：User Flash |
| <code>0x0C</code> | <code>BUILD_ID</code> | RO | 平台构建标识 |
| <code>0x10</code> | <code>MEMORY_KIB</code> | RO | 位 <code>31:16</code> 为 SRAM KiB，位 <code>15:0</code> 为 ROM KiB |

应用在使用可选硬件前，应检查 <code>CHIP_ID</code>、ABI 主版本和所需特性位。<code>omcu_hw_abi_is_compatible()</code> 提供了完成该检查的首个 C 辅助函数。
