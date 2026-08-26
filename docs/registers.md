# OpenMCU ABI 0.9 寄存器参考

所有 MMIO 寄存器为 32-bit、小端、4-byte 对齐。ABI 主版本为 0 时，本文件列出的既有地址不变；
应用应先读取 `SYSCTRL.CHIP_ID`、ABI 主版本和 `FEATURES`，再使用可选外设。机器可读的唯一来源是
[`spec/omcu-v0.json`](../spec/omcu-v0.json)，C 头文件 [`sdk/include/omcu_regs.h`](../sdk/include/omcu_regs.h)
由它生成。面向 Tang 产品的完整引脚、电气、复用和外设合同见
[中文外设与引脚完整规格书](zh-CN/peripheral-pin-specification.md)；升级流程见
[中文工程数据手册](zh-CN/datasheet.md)。

`RW1C` 表示“写 1 清除”；未列出的位读为 0、写入时忽略，除非该外设另有说明。除 SRAM 的普通访问和 User Flash 明确列出的擦除命令外，**所有 MMIO 配置、命令和 RW1C 写均须使用完整自然对齐的 32-bit 写（`wstrb=1111`）**；字节或半字 MMIO 写被忽略。C SDK 的寄存器类型为 `volatile uint32_t`，不要把外设寄存器转换为 `uint8_t *` 或 `uint16_t *`。

## 地址总表

| 外设 | 基址 |
| --- | ---: |
| GPIO0 | `0x4000_0000` |
| UART0 | `0x4000_1000` |
| TIMER0 | `0x4000_2000` |
| SPI0 | `0x4000_3000` |
| I2C0 | `0x4000_4000` |
| WDT0 | `0x4000_5000` |
| PWM0 | `0x4000_6000` |
| IRQCTRL | `0x4000_7000` |
| UART1 | `0x4000_8000` |
| TIMER1 | `0x4000_9000` |
| PWM1 | `0x4000_A000` |
| PINMUX | `0x4000_B000` |
| ALARM0 | `0x4000_C000` |
| PULSE0 | `0x4000_D000` |
| FAULT0 | `0x4000_E000` |
| SYSCTRL | `0x4000_F000` |

## GPIO0 — `0x4000_0000`

Tang 产品公开 GPIO0 bit 0..11。bit 0..5 同时镜像到板载低有效 LED；LED 不是另一组私有 GPIO。
所有输入先经过两级同步；复位兼容的默认路径是整个 12-bit 端口共享的稳定滤波。若
`FILTER_CTRL.INDEPENDENT_ENABLE=1`，`FILTER_MASK` 选中的 pin 改用相互独立的 2/4/8 样本一致性
滤波，未选中的 pin 保持两级同步、没有额外等待。因此 GPIO 仍不是异步高速采样接口。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `OUT` | RW | 输出锁存。 |
| `0x04` | `OUT_SET` | WO | 写 1 置位对应 `OUT`。 |
| `0x08` | `OUT_CLR` | WO | 写 1 清零对应 `OUT`。 |
| `0x0C` | `OUT_XOR` | WO | 写 1 翻转对应 `OUT`。 |
| `0x10` | `OE` | RW | 输出使能；0 释放为高阻（若当前 pinmux 未接管）。 |
| `0x14` | `OE_SET` | WO | 写 1 置位对应 `OE`。 |
| `0x18` | `OE_CLR` | WO | 写 1 清零对应 `OE`。 |
| `0x20` | `IN` | RO | 采样输入。 |
| `0x24` | `RISE_EN` | RW | 上升沿 IRQ 使能。 |
| `0x28` | `FALL_EN` | RW | 下降沿 IRQ 使能。 |
| `0x2C` | `IRQ_STATUS` | RW1C | 锁存的边沿事件。 |
| `0x30` | `FILTER_MASK` | RW | 独立模式的 pin 选择掩码；仅在 `FILTER_CTRL.INDEPENDENT_ENABLE=1` 时生效。 |
| `0x34` | `FILTER_CYCLES` | RW | low8：默认共享模式的 `N`；整个端口须有 N+1 个不变同步样本才接受。独立模式下保留但不参与判定。 |
| `0x38` | `SNAPSHOT_CTRL` | RW | bit0 ENABLE，bit1 GPIO0 IRQ_ENABLE，bit2 OVERWRITE。 |
| `0x3C` | `SNAPSHOT_RISE_EN` | RW | `RISE_EN` 别名；同一掩码同时决定 GPIO IRQ/普通快照边沿。 |
| `0x40` | `SNAPSHOT_FALL_EN` | RW | `FALL_EN` 别名；同一掩码同时决定 GPIO IRQ/普通快照边沿。 |
| `0x44` | `SNAPSHOT_STATUS` | RW1C / RO | bit0 VALID、bit1 OVERFLOW 可 W1C；bit2 FORCED 为 FAULT0 优先快照标记。 |
| `0x48` | `SNAPSHOT_EVENT` | RO | 被锁存的边沿位掩码。 |
| `0x4C` | `SNAPSHOT_INPUT` | RO | 被锁存的过滤后输入。 |
| `0x50` | `SNAPSHOT_IRQ` | RO | 锁存时 IRQCTRL active CPU IRQ 掩码。 |
| `0x54` | `SNAPSHOT_RESET` | RO | 锁存时 retained reset cause。 |
| `0x58` | `SNAPSHOT_TICKS` | RO | 锁存时 `RUN_TICKS` 的低 32 位。 |
| `0x5C` | `FILTER_CTRL` | RW | bit0 `INDEPENDENT_ENABLE`；bits2:1 深度：`00` 2、`01` 4、`10/11` 8 个连续相同同步样本。 |

改写 `FILTER_MASK`、`FILTER_CYCLES` 或 `FILTER_CTRL` 会开始新的滤波周期；硬件保留已经接受的
输出，直到新配置确认稳定的新电平。使用 SDK 时，旧共享语义调用
`omcu_gpio_configure_filter()`；需要按针独立条件化时调用
`omcu_gpio_configure_independent_filter(mask, OMCU_GPIO_FILTER_CTRL_DEPTH_2/4/8)`。

## UART0 / UART1 — `0x4000_1000` / `0x4000_8000`

两个 UART 寄存器格式相同，均为 8-N-1。`BAUDDIV` 为每 bit 系统时钟数减 1；27 MHz 下 233
约为 115200 baud。UART1 只有在 `FEATURES.UART1` 与 `PINMUX.UART1_ENABLE` 均满足时才驱动
GPIO10/11；UART0 始终用于产品 Bootloader/恢复。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `DATA` | RW | 完整 32-bit 写的 `[7:0]`：TX 字节；读 RX 字节且消费 `RX_VALID`。 |
| `0x04` | `STATUS` | RW | bit0 `TX_READY`，bit1 `RX_VALID`，bit2 `RX_OVERRUN`（W1C），bit3 `RX_FRAMING_ERROR`（W1C），bit4 `TX_BUSY`。 |
| `0x08` | `BAUDDIV` | RW | `[15:0]`：每 bit 时钟数减 1。 |
| `0x0C` | `CTRL` | RW | bit0 `TX_ENABLE`，bit1 `RX_ENABLE`，bit2 `RX_IRQ_ENABLE`。 |

UART0 RX 对应 CPU IRQ bit 9，UART1 RX 对应 bit 14；先读 `DATA` 再按中断约定清除/确认。

## TIMER0 — `0x4000_2000`

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | bit0 `ENABLE`，bit1 `IRQ_ENABLE`，bit2 `AUTO_RELOAD`。 |
| `0x04` | `PRESCALE` | RW | `[15:0]`：每个计数 tick 的时钟数减 1。 |
| `0x08` | `COUNT` | RW | 当前计数。 |
| `0x0C` | `COMPARE` | RW | 比较值。 |
| `0x10` | `STATUS` | RW1C | bit0 `PENDING`。 |

非自动重装时到达比较值停止；自动重装时归零继续计数。

## SPI0 — `0x4000_3000`

SPI0 是 MSB-first、CPOL=0/CPHA=0（mode 0）的 8-bit 主机。`START` 完成一个字节；
`CTRL.CS_HOLD` 允许软件组合多字节帧，例如 MCP3008、MCP4921 或 W5500 寄存器事务。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `DATA` | RW | 完整 32-bit 写的 `[7:0]`：下一个 TX 字节 / 已完成 RX 字节。 |
| `0x04` | `STATUS` | RW1C | bit0 `BUSY`，bit1 `DONE`（W1C），bit5 `CS_ACTIVE`（RO）。 |
| `0x08` | `CLKDIV` | RW | `[15:0]`：SCK 半周期时钟数减 1。 |
| `0x0C` | `CTRL` | RW | bit0 `ENABLE`，bit1 `DONE_IRQ_ENABLE`，bit2 `CS_HOLD`。 |
| `0x10` | `START` | WO | bit0=1，在 enable 且非 busy 时发起一个字节。 |

Tang 的 SPI0 与 TF 信号组共享；不应与插入/访问 microSD 的场景并用。

## I2C0 — `0x4000_4000`

I2C0 是开漏、单主机、字节级引擎。外部必须有合适的 3.3 V 上拉。它没有 FIFO、DMA、仲裁丢失
处理、总线恢复或自动超时；上层应设置超时/看门狗策略。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `DATA` | RW | 完整 32-bit 写的 low8：下一个 TX 字节 / 已完成 RX 字节。 |
| `0x04` | `STATUS` | RW1C | bit0 `BUSY`，bit1 `DONE`，bit2 `ACK_ERROR`，bit3 `COMMAND_ERROR`，bit4 `BUS_ACTIVE`（RO）。 |
| `0x08` | `CLKDIV` | RW | `[15:0]`：SCL 高/低相位时钟数减 1。 |
| `0x0C` | `CTRL` | RW | bit0 `ENABLE`，bit1 `DONE_IRQ_ENABLE`。禁用会释放两条线。 |
| `0x10` | `CMD` | WO | 只能精确选择 bit0 `START`、bit1 `STOP`、bit2 `WRITE`、bit3 `READ_ACK`、bit4 `READ_NACK` 中之一。 |

`WRITE/READ/STOP` 需要此前 START；新的 START 是重复 START。终止/拒绝命令均置 `DONE`，
NACK 置 `ACK_ERROR`，非法序列置 `COMMAND_ERROR`。

## WDT0 — `0x4000_5000`

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | bit0 `ENABLE`，bit1 `RESET_ENABLE`，bit2 `IRQ_ENABLE`。 |
| `0x04` | `TIMEOUT` | RW | 计数到此值即到期。 |
| `0x08` | `FEED` | WO | 只接受 `0x51F1_5EED`。 |
| `0x0C` | `STATUS` | RW1C / RO | bit0 `EXPIRED`，bit1 `RESET_REQUEST`（活动脉冲 RO），bit2 `PRETIMEOUT`，bit3 `WINDOW_VIOLATION`，bit4 `HEARTBEAT_MISSING`，bit5 `FEED_REJECTED`。 |
| `0x10` | `PRETIMEOUT` | RW | 非零时在该 count 置预警；仅完整 32-bit 写。 |
| `0x14` | `WINDOW_MIN` | RW | 启用窗口时，早于该 count 的喂狗被拒绝；仅完整 32-bit 写。 |
| `0x18` | `HEARTBEAT_REQUIRED` | RW | low8：本 epoch 喂狗前必须已报告的任务 mask；仅完整 32-bit 写。 |
| `0x1C` | `HEARTBEAT_SEEN` | RO | low8：当前 epoch 已报告任务。 |
| `0x20` | `HEARTBEAT_KICK` | WO | low8 写 1 累积任务进度。 |
| `0x24` | `COUNT` | RO | 当前 32-bit count。 |

`CTRL` bit3 `PRETIMEOUT_IRQ_ENABLE`、bit4 `WINDOW_ENABLE`、bit5 `HEARTBEAT_ENABLE`。预警不自动复位；
窗口违例或缺失 heartbeat 会拒绝该次喂狗并使 watchdog 进入 expired 诊断状态。

## PWM0 — `0x4000_6000`

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | bit0 `ENABLE`，bit1 `INVERT`。 |
| `0x04` | `PRESCALE` | RW | `[15:0]`：每 tick 时钟数减 1。 |
| `0x08` | `PERIOD` | RW | 包含式顶值。 |
| `0x0C` | `DUTY` | RW | `COUNT < DUTY` 时输出有效。 |
| `0x10` | `COUNT` | RO | 当前计数。 |

## IRQCTRL — `0x4000_7000`

IRQCTRL 不是标准 RISC-V PLIC。寄存器掩码使用 CPU IRQ bit 位置，而不是紧凑索引；
`OMCU_IRQ_EXTERNAL_MASK = 0x0007_FF00`。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `PENDING` | RO | 锁存/当前源的 CPU bit 掩码。 |
| `0x04` | `ENABLE` | RW | 逐源投递使能。 |
| `0x08` | `CLEAR` | WO | 写 1 清除锁存和软件 force 位。 |
| `0x0C` | `FORCE` | WO | 写 1 设置软件 pending 位。 |
| `0x10` | `ACTIVE` | RO | `PENDING & ENABLE`，会投递 CPU。 |
| `0x14` | `HIGHEST` | RO | 最低编号的活动 CPU IRQ bit；无源时为 0。 |

| CPU bit | 常量 | 源 |
| ---: | --- | --- |
| 8 | `OMCU_IRQ_GPIO0` | GPIO 边沿。 |
| 9 | `OMCU_IRQ_UART0` | UART0 RX。 |
| 10 | `OMCU_IRQ_TIMER0` | TIMER0。 |
| 11 | `OMCU_IRQ_SPI0` | SPI0 DONE。 |
| 12 | `OMCU_IRQ_I2C0` | I2C0 DONE/错误。 |
| 13 | `OMCU_IRQ_WDT0` | WDT0 到期。 |
| 14 | `OMCU_IRQ_UART1` | UART1 RX。 |
| 15 | `OMCU_IRQ_TIMER1` | TIMER1 compare/capture/encoder。 |
| 16 | `OMCU_IRQ_ALARM0` | ALARM0 任一路 compare pending。 |
| 17 | `OMCU_IRQ_PULSE0` | PULSE0 测量边沿。 |
| 18 | `OMCU_IRQ_FAULT0` | FAULT0 首次锁存。 |

## UART1 — `0x4000_8000`

寄存器格式与 UART0 完全相同；只在 `FEATURES.UART1` 存在时使用。将 UART1 接到 Tang J5.18/J5.19
前，软件必须设置 `PINMUX.CTRL.UART1_ENABLE`（SDK `omcu_tn9k_uart1_init()` 会完成此步骤）。

## TIMER1 — `0x4000_9000`

TIMER1 是**明确的资源受控 16-bit**外设。`COUNT`、`COMPARE`、`CAPTURE_A/B` 的有效位均为
`[15:0]`；`ENCODER` 为低 16-bit 的有符号二补码，读取时符号扩展；`FILTER` 仅 `[7:0]`。
MMIO 总线仍以 32-bit 访问，写入高位不改变这些字段。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | bit0 `ENABLE`，bit1 `IRQ_ENABLE`，bit2 `AUTO_RELOAD`，bit3/4 `CAPTURE_A/B_ENABLE`，bit5/6 `CAPTURE_A/B_FALLING`，bit7 `QUADRATURE_ENABLE`，bit8 `QUADRATURE_REVERSE`。 |
| `0x04` | `PRESCALE` | RW | `[15:0]`：每个 timer tick 的时钟数减 1。 |
| `0x08` | `COUNT` | RW | `[15:0]` 当前时间戳计数。 |
| `0x0C` | `COMPARE` | RW | `[15:0]` 比较值。 |
| `0x10` | `FILTER` | RW | `[7:0]`：`N` 代表 `N+1` 个连续同步样本。 |
| `0x14` | `CAPTURE_A` | RO | `[15:0]` 最近合格 A 边沿的时间戳。 |
| `0x18` | `CAPTURE_B` | RO | `[15:0]` 最近合格 B 边沿的时间戳。 |
| `0x1C` | `ENCODER` | RW | `[15:0]` 有符号环绕位置；读回符号扩展。 |
| `0x20` | `STATUS` | RW1C | bit0 `COMPARE`，bit1 `CAPTURE_A`，bit2 `CAPTURE_B`，bit3 `ENCODER_STEP`，bit4 `ENCODER_ILLEGAL`；bit5/6 为滤波后 A/B 输入，bit7 为最近方向（RO）。 |

两根输入固定经过两级同步和稳定滤波。`FILTER=0` 是同步后立即接受，`FILTER=N` 需要 `N+1`
个连续样本；这不是毫秒级机械去抖或异步高速计数合同。启用 Tang pinmux 后，A/B 对应 GPIO8/9。

## PWM1 — `0x4000_A000`

PWM1 为四路同相、共享分频器和计数器的边沿对齐输出。`PERIOD`、所有 `DUTY` 和 `COUNT` 仅
使用低 16-bit；写入高位不改变字段。disable 时四路输出均为确定低电平，即使 invert 位仍被设置。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | bit0 `ENABLE`；bit4..7 分别为 CH0..3 `INVERT`。 |
| `0x04` | `PRESCALE` | RW | `[15:0]`：共享计数 tick 时钟数减 1。 |
| `0x08` | `PERIOD` | RW | `[15:0]` 包含式共享 top。 |
| `0x0C` | `DUTY0` | RW | `[15:0]`，`COUNT < DUTY0` 时 CH0 有效。 |
| `0x10` | `DUTY1` | RW | `[15:0]`，CH1。 |
| `0x14` | `DUTY2` | RW | `[15:0]`，CH2。 |
| `0x18` | `DUTY3` | RW | `[15:0]`，CH3。 |
| `0x1C` | `COUNT` | RO | `[15:0]` 当前共享计数。 |

四路 duty 更新没有影子寄存器/原子多通道提交，功率级产品必须自行处理安全更新。

## PINMUX — `0x4000_B000`

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | bit0 `UART1_ENABLE`（GPIO10/11），bit1 `PWM1_ENABLE`（GPIO4..7），bit2 `TIMER1_ENABLE`（GPIO8/9），bit3 `PULSE0_ENABLE`（GPIO0..2），bit4 `FAULT0_ENABLE`（GPIO3）。清零归还 GPIO 所有权。 |

pinmux 只是 FPGA 内所有权切换，不能忽略 RGB LCD 共线、板卡 Bank 电压或外接功率级要求。

## ALARM0 — `0x4000_C000`

ALARM0 是复用 TIMER0 低 16-bit 时基的两个并行比较通道。TIMER0 独占预分频、计数、停止与环绕；
ALARM0 只在每个 TIMER0 tick 评估两个 deadline，因此可以同 tick 触发，且不是扫描轮询器。除 `CTRL`
外的下列可写配置均只接受完整 32-bit 写。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW/RO | bit0 `COMPARE_ENABLE`；bit1 `TIMEBASE_RUNNING`（RO，TIMER0 ENABLE 镜像）。 |
| `0x04` | `PRESCALE` | RO | low16：TIMER0 PRESCALE 镜像；写忽略。 |
| `0x08` | `COUNT` | RO | low16：TIMER0 COUNT 镜像；写忽略。 |
| `0x0C` | `CHANNEL_ENABLE` | RW | bit0/1 使能通道 0/1。 |
| `0x10` | `IRQ_ENABLE` | RW | bit0/1 选择哪个 pending 使 ALARM0 IRQ 有效。 |
| `0x14` | `PERIODIC` | RW | bit0/1：事件后 compare 加 `PERIODn`。 |
| `0x18` | `PENDING` | RW1C | bit0/1 compare pending。 |
| `0x1C` | `COMPARE0` | RW | low16：通道 0 absolute deadline。 |
| `0x20` | `COMPARE1` | RW | low16：通道 1 absolute deadline。 |
| `0x24` / `0x28` | `COMPARE2/3` | RO | 保留，读 0。 |
| `0x2C` | `PERIOD0` | RW | low16：通道 0 事件后增量；零为 one-shot。 |
| `0x30` | `PERIOD1` | RW | low16：通道 1 事件后增量；零为 one-shot。 |
| `0x34` / `0x38` | `PERIOD2/3` | RO | 保留，读 0。 |

比较条件为 `TIMER0.COUNT[15:0] == COMPAREn`，这使周期 compare 可以正确跨越 16-bit 环绕。应优先用
`omcu_alarm0_schedule_after()` 创建相对 deadline（不可为零且应留出 MMIO 配置时间）；
`omcu_alarm0_start(prescale)` 配置 TIMER0 为无 IRQ 的自由运行时基，已有 TIMER0 所有者时改用
`omcu_alarm0_attach_timer0()`。

## PULSE0 — `0x4000_D000`

PULSE0 一次只在 GPIO0/J5.8、GPIO1/J5.9、GPIO2/J5.10 中选择一路；PINMUX 接管后三根 pad 都释放
GPIO 输出。所选输入独立经过两级同步及 N+1 样本稳定滤波，输出 16-bit 环绕计数和最近两个边沿间的
`RUN_TICKS` 低 16-bit 差值。它不是异步高速计数器或三路并行捕获器。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | bit0 ENABLE，bit1 IRQ_ENABLE；完整 word 写。 |
| `0x04` | `INPUT_SELECT` | RW | 0/1/2 对应 GPIO0/1/2；切换会清空测量 epoch。 |
| `0x08` | `EDGE` | RW | bit0 `FALLING`（0 为 rising）；完整 word 写。 |
| `0x0C` | `FILTER` | RW | low8：`N` 表示 N+1 个连续不同的同步样本；完整 word 写。 |
| `0x10` | `STATUS` | RW1C / RO | bit0 PENDING（W1C），bit1 过滤后输入，bit2 PERIOD_VALID，bit5..4 选择。 |
| `0x14` | `CLEAR` | WO | bit0 清当前 epoch 的计数、周期、tick、valid 与 pending。 |
| `0x18` | `COUNT` | RO | low16：环绕边沿计数。 |
| `0x1C` | `PERIOD` | RO | low16：最近两次有效边沿的 run-tick 差。 |
| `0x20` | `LAST_TICK` | RO | low16：最近边沿 timestamp。 |

## FAULT0 — `0x4000_E000`

FAULT0 使用 GPIO3/J5.11，经 PINMUX 接管后作输入。它有独立两级同步、N+1 样本滤波和首个故障锁存；
可选地将 PWM0/PWM1 拉低、将全部 12 路公开 GPIO 释放高阻，并强制 GPIO0 的共享快照。它不等于异步
急停或功能安全认证。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | 完整 32-bit 写：bit0 ENABLE、bit1 ACTIVE_HIGH、bit2 IRQ_ENABLE、bit3 GATE_PWM0、bit4 GATE_PWM1、bit5 GATE_GPIO。 |
| `0x04` | `FILTER` | RW | 完整 32-bit 写的 low8：`N` 表示 N+1 个连续不同的同步样本。 |
| `0x08` | `GPIO_HIZ_MASK` | RO | 固定为所有公开 GPIO 位；写入忽略。 |
| `0x0C` | `STATUS` | RW / RO | bit0 TRIPPED、bit1 filtered input、bit2 PINMUX claim、bit3 CLEAR_REJECTED（完整 32-bit W1C）、bit4 current active。 |
| `0x10` | `CLEAR` | WO | 仅完整 `OMCU_FAULT_CLEAR_MAGIC`，且输入已 claim 并处于 inactive 时才能清锁存。 |
| `0x14` | `SNAPSHOT_TICK` | RO | GPIO 共享快照的 run-tick。 |
| `0x18` | `SNAPSHOT_GPIO` | RO | GPIO 共享快照的输入状态。 |
| `0x1C` | `SNAPSHOT_IRQ` | RO | GPIO 共享快照的 IRQCTRL active。 |
| `0x20` | `SNAPSHOT_RESET` | RO | GPIO 共享快照的 reset cause。 |

## SYSCTRL — `0x4000_F000`

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CHIP_ID` | RO | `0x4F4D_4355`（ASCII `OMCU`）。 |
| `0x04` | `ABI` | RO | `[31:16]` 主版本、`[15:0]` 次版本；当前为 `0x0000_0009`。 |
| `0x08` | `FEATURES` | RO | bit0..19：基础外设、P1、GPIO_RELIABILITY、ALARM0、PULSE0、FAULT0、WDT_SUPERVISOR；Tang 产品为 `0x000F_FFFF`。 |
| `0x0C` | `BUILD_ID` | RO | 平台构建标识。 |
| `0x10` | `MEMORY_KIB` | RO | `[31:16]` SRAM KiB，`[15:0]` ROM KiB；产品为 44 / 4。 |
| `0x14` | `RESET_CAUSE` | RO | one-hot：bit0 EXTERNAL，bit1 WATCHDOG，bit2 SOFTWARE。 |
| `0x18` | `RUN_TICKS_LO` | RO | 当前 SoC 启动后的 64-bit 时钟 tick 低字。 |
| `0x1C` | `RUN_TICKS_HI` | RO | 当前 SoC 启动后的 64-bit 时钟 tick 高字。 |
| `0x20` | `RESET_COUNT` | RO | 本次外部复位后 watchdog/software 内部复位次数。 |
| `0x24` | `BOOT_CTRL` | RW | bit0 `REQUEST_PENDING`，bit1 `REQUEST_SUPPORTED`；完整 32-bit 写 `0xB007_10AD` 请求 Bootloader，完整 32-bit 写 `0xACCE_5501` 仅供 Boot ROM 确认消费。 |

`BOOT_CTRL` 请求只在具有 `DIAGNOSTICS` 和 `USER_FLASH` 的产品位流受支持。部分字写或任意其他值
都会被忽略；应用应调用 `omcu_tn9k_request_bootloader()`，Boot ROM 内部才调用确认 helper。读取
64-bit tick 时使用 `omcu_sysctrl_run_ticks()` 的 high/low/high 一致性读取，避免 rollover 撕裂。
