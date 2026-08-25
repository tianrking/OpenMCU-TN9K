# OpenMCU ABI 0.6 寄存器参考

所有 MMIO 寄存器为 32-bit、小端、4-byte 对齐。ABI 主版本为 0 时，本文件列出的既有地址不变；
应用应先读取 `SYSCTRL.CHIP_ID`、ABI 主版本和 `FEATURES`，再使用可选外设。机器可读的唯一来源是
[`spec/omcu-v0.json`](../spec/omcu-v0.json)，C 头文件 [`sdk/include/omcu_regs.h`](../sdk/include/omcu_regs.h)
由它生成。面向 Tang 产品的完整引脚、电气、复用和外设合同见
[中文外设与引脚完整规格书](zh-CN/peripheral-pin-specification.md)；升级流程见
[中文工程数据手册](zh-CN/datasheet.md)。

`RW1C` 表示“写 1 清除”；未列出的位读为 0、写入时忽略，除非该外设另有说明。

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
| SYSCTRL | `0x4000_F000` |

## GPIO0 — `0x4000_0000`

Tang 产品中 bit 0..5 是低有效 LED 逻辑位；bit 6..17 是 12 路外扩 GPIO。所有位受当前平台实现
宽度限制，GPIO 输入不是异步高速采样接口。

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

## UART0 / UART1 — `0x4000_1000` / `0x4000_8000`

两个 UART 寄存器格式相同，均为 8-N-1。`BAUDDIV` 为每 bit 系统时钟数减 1；27 MHz 下 233
约为 115200 baud。UART1 只有在 `FEATURES.UART1` 与 `PINMUX.UART1_ENABLE` 均满足时才驱动
GPIO10/11；UART0 始终用于产品 Bootloader/恢复。

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `DATA` | RW | `[7:0]`：写 TX 字节；读 RX 字节且消费 `RX_VALID`。 |
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
| `0x00` | `DATA` | RW | `[7:0]`：下一个 TX 字节 / 已完成 RX 字节。 |
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
| `0x00` | `DATA` | RW | 下一个 TX 字节 / 已完成 RX 字节。 |
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
| `0x0C` | `STATUS` | RW1C | bit0 `EXPIRED`；bit1 `RESET_REQUEST` 为活动脉冲观察位。 |

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
`OMCU_IRQ_EXTERNAL_MASK = 0x0000_FF00`。

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
| `0x00` | `CTRL` | RW | bit0 `UART1_ENABLE`（GPIO10/11），bit1 `PWM1_ENABLE`（GPIO4..7），bit2 `TIMER1_ENABLE`（GPIO8/9）。清零归还 GPIO 所有权。 |

pinmux 只是 FPGA 内所有权切换，不能忽略 RGB LCD 共线、板卡 Bank 电压或外接功率级要求。

## SYSCTRL — `0x4000_F000`

| 偏移 | 名称 | 访问 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CHIP_ID` | RO | `0x4F4D_4355`（ASCII `OMCU`）。 |
| `0x04` | `ABI` | RO | `[31:16]` 主版本、`[15:0]` 次版本；当前为 `0x0000_0006`。 |
| `0x08` | `FEATURES` | RO | bit0..14：GPIO0、UART0、TIMER0、SPI0、I2C0、WDT0、PWM0、IRQCTRL、UART1、TIMER1、PWM1、DIAGNOSTICS、PINMUX、GPIO_EXPANSION、USER_FLASH。Tang 产品为 `0x0000_7FFF`。 |
| `0x0C` | `BUILD_ID` | RO | 平台构建标识。 |
| `0x10` | `MEMORY_KIB` | RO | `[31:16]` SRAM KiB，`[15:0]` ROM KiB；产品为 44 / 8。 |
| `0x14` | `RESET_CAUSE` | RO | one-hot：bit0 EXTERNAL，bit1 WATCHDOG，bit2 SOFTWARE。 |
| `0x18` | `RUN_TICKS_LO` | RO | 当前 SoC 启动后的 64-bit 时钟 tick 低字。 |
| `0x1C` | `RUN_TICKS_HI` | RO | 当前 SoC 启动后的 64-bit 时钟 tick 高字。 |
| `0x20` | `RESET_COUNT` | RO | 本次外部复位后 watchdog/software 内部复位次数。 |
| `0x24` | `BOOT_CTRL` | RW | bit0 `REQUEST_PENDING`，bit1 `REQUEST_SUPPORTED`；完整 32-bit 写 `0xB007_10AD` 请求 Bootloader，完整 32-bit 写 `0xACCE_5501` 仅供 Boot ROM 确认消费。 |

`BOOT_CTRL` 请求只在具有 `DIAGNOSTICS` 和 `USER_FLASH` 的产品位流受支持。部分字写或任意其他值
都会被忽略；应用应调用 `omcu_tn9k_request_bootloader()`，Boot ROM 内部才调用确认 helper。读取
64-bit tick 时使用 `omcu_sysctrl_run_ticks()` 的 high/low/high 一致性读取，避免 rollover 撕裂。
