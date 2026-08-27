# Tang Nano 9K 硬件与引脚

> **主规格书入口：**所有已约束 package pad、原理图 J5 逻辑映射、PINMUX 所有权、外设寄存器和不支持能力以
> [《OpenMCU-TN9K 外设与引脚完整规格书》](peripheral-pin-specification.md)为准。
> 本页专注于接线、电气注意事项、实验步骤和实体板 HIL，不重复维护另一份引脚真相源。

## 板级边界

目标板是 `GW1NR-LV9QN88PC6/I5`（GW1N-9C）。Sipeed 的 Tang Nano 9K 产品资料列出
GW1NR-9、6 个 LED、2 个按键、32 Mbit SPI Flash、64 Mbit PSRAM、USB 下载器和两组
扩展 I/O；OpenMCU 使用其中 FPGA 逻辑和已约束的 I/O，不会把板载 PSRAM/Flash
自动宣称为 MCU 的已验证程序存储器。

本仓库的约束文件是
[`rtl/platform/tangnano9k/project/omcu_tn9k_bringup.cst`](../../rtl/platform/tangnano9k/project/omcu_tn9k_bringup.cst)。
下表同时按 [Sipeed 官方 6202 原理图](https://dl.sipeed.com/fileList/TANG/Nano%209K/2_Schematic/Tang_Nano_9k_3672_Schematic.pdf)
核对了 J5 网络与 package pad；2026-08-27 的单板无夹具自检还通过 UART0、12 路 GPIO pad 回读、
PWM1 pad 回读、UART1 TX pad、SPI 空载与 I2C 空载 START/STOP。生产前仍必须确认手中板卡 revision、
测量真实电平，并完成外部回环/目标器件验收。

接线时不要寻找 PCB 上未逐针印出的 `J5.x`。本文把**元件面朝上、USB-C 在顶部**时的左侧排针
从上向下命名为 `L1..L24`；它与原理图 `J5.1..24` 一一对应。Sipeed 官方 Pinmap 在孔位旁显示的是
FPGA package pin，完整实物图与回环位置见[《MCU 外设实体板验收》](mcu-peripheral-qualification.md)。

| OpenMCU 功能 | 顶层端口/逻辑 GPIO | package pad | 用途和注意事项 |
| --- | --- | ---: | --- |
| 时钟 | `clk_27m_i` | 52 | 板载 27 MHz，SDC 约束为 27 MHz。 |
| 外部复位 | `resetn_i` | 4 | 低有效；顶层异步断言、同步释放。 |
| UART0 TX/RX | `uart_tx_o` / `uart_rx_i` | 17 / 18 | 3.3 V 逻辑，默认 SDK 115200 8-N-1；PCB 已接板载 BL702 USB-UART，使用 USB-C 时无需外接跳线。 |
| LED0..5 | GPIO0[0..5] / `led_n_o[0..5]` | 10,11,13,14,15,16 | 板上 LED 为低电平点亮；SDK 逻辑 GPIO 为高表示“点亮”。 |
| SPI0 CS/MOSI/SCK/MISO | `spi0_*` | 38/37/36/39 | 左排 L1/L2/L3/L4（原理图 J5.1..4），与 TF-card 信号共享；使用时不得同时插入或访问 microSD。 |
| I2C0 SCL/SDA | `i2c0_scl_io` / `i2c0_sda_io` | 26 / 27 | 左排 L6/L7（原理图 J5.6/7），真正开漏；外部必须提供合适的 3.3 V 上拉。 |
| PWM0 | `pwm0_o` | 25 | 左排 L5（原理图 J5.5），单路边沿对齐 PWM。 |
| PULSE0 输入（复用） | GPIO0..2 / `gpio_io[0:2]` | 28 / 29 / 30 | `PINMUX.CTRL.PULSE0_ENABLE=1` 后三根 GPIO 输出全被释放，PULSE0 一次只测一路。 |
| FAULT0 输入（复用） | GPIO3 / `gpio_io[3]` | 33 | `PINMUX.CTRL.FAULT0_ENABLE=1` 后作为 FAULT0 输入；可门控 PWM/GPIO，但不是安全认证急停。 |
| PWM1 CH0..3（复用） | GPIO4..7 / `gpio_io[4:7]` | 34 / 40 / 35 / 41 | 默认仍是 GPIO；`PINMUX.CTRL.PWM1_ENABLE=1` 后为四路共享计数器 PWM，对应左排 L12..L15（J5.12..15）。 |
| TIMER1 A/B 输入（复用） | GPIO8/9 / `gpio_io[8:9]` | 42 / 51 | 默认仍是 GPIO；`PINMUX.CTRL.TIMER1_ENABLE=1` 后两根 pad 被释放为输入，对应左排 L16/L17（J5.16/17），可作同步滤波捕获或正交编码器 A/B。 |
| 扩展 GPIO 档案 | GPIO0[0..11] / `gpio_io[0..11]` | 28,29,30,33,34,40,35,41,42,51,53,54 | 12 路可输入、输出或高阻；GPIO0[0..5] 同时镜像 LED0..5，`gpio_io[3..11]` 与 RGB LCD 共线。 |
| UART1 TX/RX（复用） | GPIO10/11 / `gpio_io[10:11]` | 53 / 54 | 默认仍是 GPIO；`PINMUX.CTRL.UART1_ENABLE=1` 后为 UART1 TX/RX，对应左排 L18/L19（J5.18/19）。 |

`GPIO0[0..5]` 会镜像板载低有效 LED，但并非 LED 专用的私有寄存器位；SDK 中它们仍是
`OMCU_TN9K_GPIO0` 至 `OMCU_TN9K_GPIO5`。全部 12 路逻辑 GPIO 均遵守 `OE`：软件清掉 `OE` 后，FPGA pad 会释放为
高阻，而不是把“1”推到外部总线。

| SDK GPIO | `gpio_io` | 实物左排（原理图 J5） | package pad | 复用边界 |
| --- | ---: | ---: | ---: | --- |
| GPIO0..2 | 0..2 | L8..L10（J5.8..10） | 28 / 29 / 30 | 现有公开的 3.3 V 数字组。 |
| GPIO3..11 | 3..11 | L11..L19（J5.11..19） | 33 / 34 / 40 / 35 / 41 / 42 / 51 / 53 / 54 | 3.3 V，但与 RGB LCD FPC 的 DE/VS/HS/CLK/B 线共用；不能和 RGB LCD 同时使用。 |

该档案已经具有 RTL 顶层、CST、数字仿真和无负载实体 pad 自读覆盖，但尚未完成全部外部线缆、
显示复用和目标器件 HIL。它不包含 J6 的 1.8 V 信号、HDMI 对、JTAG/MODE/DONE 或“所有未用 IOB”。
固定回环夹具和逐项证据等级见[《MCU 外设实体板验收》](mcu-peripheral-qualification.md)。

## UART1、PWM1、TIMER1、PULSE0、FAULT0 与显式 pinmux

UART0 始终保留给 Bootloader、下载和默认日志，并通过板载 BL702 随 USB-C 枚举为主机串口；
它不属于六线回环夹具。需要第二路设备串口时，ABI 0.9 在 J5 的
两个已约束 3.3 V pad 上提供无 FIFO 的 UART1：TX 为 GPIO10 / J5.18 / package pad 53，RX
为 GPIO11 / J5.19 / package pad 54。复位时这两个 pad 仍是普通高阻 GPIO，不会因为 FPGA
中存在 UART1 而被暗中占用。

```c
#include "omcu_tn9k.h"

if (!omcu_tn9k_uart1_init(omcu_tn9k_uart_bauddiv(115200u), true)) {
  /* 位流没有 UART1/PINMUX 特性时不要访问 UART1 寄存器。 */
}
omcu_uart1_write_byte('U');
```

该 helper 先配置 UART1，再写 `PINMUX.CTRL.UART1_ENABLE`。启用后顶层强制 TX 为输出，
并把 RX pad 释放为输入；通用 GPIO 的 `OE` 不再能与 UART1 RX 争用。要归还两根线给 GPIO，
调用 `omcu_tn9k_uart1_release_pins()`。GPIO10/11 同属于 RGB-LCD 共线组，因此与 RGB LCD
不可同时使用；首次连接前应以 3.3 V USB 串口、短线、共地和逻辑分析仪完成 HIL。

PWM1 的四路输出使用 GPIO4..7 / J5.12..15，分别为 CH0..3。它们共享一个 16-bit 分频、
16-bit 周期和计数器，因此相位一致、每路只独立设置 duty 与 invert；复位或 `CTRL.ENABLE=0`
时四根线都主动输出低电平。下面是一个 1 kHz 左右、四种占空比的安全 GPIO→PWM 切换例子：

```c
if (!omcu_tn9k_pwm1_configure(26u, 999u, 250u, 500u, 750u, 1000u, 0u)) {
  /* 位流未宣告 PWM1/PINMUX；保持 GPIO 所有权。 */
}
```

`omcu_tn9k_pwm1_configure()` 先写完四路寄存器，再设 `PINMUX.CTRL.PWM1_ENABLE`。要归还
GPIO4..7 调用 `omcu_tn9k_pwm1_release_pins()`。这四根线也与 RGB LCD 共线，只能驱动经过
3.3 V、电流和故障策略审查的逻辑输入、LED 缓冲器或外部隔离/栅极驱动级；**不得**直接接电机、
MOSFET gate、继电器或高压负载。RTL 和数字仿真不等于功率级安全验证。

TIMER1 的 A/B 输入使用 GPIO8/9 / J5.16/J5.17（package pad 42/51）。调用
`omcu_tn9k_timer1_configure()` 后，`PINMUX.CTRL.TIMER1_ENABLE` 强制释放两根 FPGA pad；即使
通用 GPIO 曾经打开 `OE`，也不会和外部编码器争用。输入先经过两级同步，再经过连续稳定样本
滤波，最后才进入时间戳捕获和 Gray 正交解码器。`FILTER=0` 表示同步后立即接受变化；
`FILTER=N` 表示同一变化必须连续观察到 `N+1` 次。27 MHz 下这不是机械去抖时间承诺：例如
`FILTER=4` 仅约为 5 个时钟周期（约 185 ns，另有同步延迟），机械开关通常需要更大的值和实测。

```c
const uint32_t ctrl = OMCU_TIMER1_CTRL_ENABLE |
                      OMCU_TIMER1_CTRL_CAPTURE_A_ENABLE |
                      OMCU_TIMER1_CTRL_CAPTURE_B_ENABLE |
                      OMCU_TIMER1_CTRL_QUADRATURE_ENABLE;

if (!omcu_tn9k_timer1_configure(0u, UINT16_MAX, 4u, ctrl)) {
  /* TIMER1/PINMUX 不存在时保持 GPIO 所有权。 */
}
```

正向状态约定为 `00 -> 01 -> 11 -> 10 -> 00`；可用 `CTRL.QUADRATURE_REVERSE` 翻转方向，
`ENCODER` 是可读写、二补码解释的 16-bit 环绕位置（读取时符号扩展为 32-bit）。两个信号同时跳变或非 Gray 转换会置
`STATUS.ENCODER_ILLEGAL`，软件应记录原因并 W1C 清除。它不是异步高速计数器，也不把原始
pad 当普通 GPIO 输入使用；高速、跨时钟、长线或抗扰要求高的编码器需要专用前端和实体板 HIL。
两根线同样与 RGB LCD 共线，不能与显示器同时启用。

PULSE0 使用 GPIO0..2 / J5.8..10。调用 `omcu_tn9k_pulse0_configure()` 后顶层会释放三根 pad 的
GPIO 输出，随后 PULSE0 只从其中一个所选输入计数。输入已经过两级同步和数字稳定滤波，但依然只适合
3.3 V、共地、低速霍尔/流量/脉冲传感器；不要接 5 V、编码器高速 A/B、无整形的长线或把它当作三路
并行频率计。

FAULT0 使用 GPIO3 / J5.11。应用应在外部物理故障实际消失后才调用 `omcu_fault0_clear()`；启用
`GATE_PWM0`、`GATE_PWM1` 或 `GATE_GPIO` 时，FPGA 只会控制对应的逻辑输出：PWM 被拉低、所有公开 GPIO
被释放高阻。它不能切断外部供电、保证外置驱动器状态、处理异步急停，也不提供功能安全认证。

## 电气安全规则

1. 不要向这些 I/O 注入 5 V。CST 将上述端口配置为 `LVCMOS33`；在连接任意模块前先
   用当前板卡原理图确认对应银行确实是 3.3 V。
2. I2C 是开漏协议。使用外部 2.2 kΩ–10 kΩ（常用 4.7 kΩ）上拉到 3.3 V；CST 的
   `PULL_MODE=UP` 只是弱内部偏置，不能替代总线电气上拉。
3. SPI0 与 TF-card 信号共享。只接一个外部 SPI 目标（或完成有明确片选隔离的设计），
   且不要并用 microSD。
4. 任何外设连线必须共地。先断电连接，先用 SRAM 下载测试，再考虑 Flash。
5. 外部输入的异步边沿会进入 GPIO 采样逻辑。高速/跨时钟信号应在外部或新增 RTL 中
   同步处理，不要把本 MCU GPIO 当作高速采样接口。
6. PULSE0、FAULT0 和普通 GPIO 的同步/滤波只说明数字采样路径；传感器的浪涌、ESD、隔离、
   接地回路、输入阈值和失效安全状态必须由外部电路承担。

## 建议的首块外设实验板

用一个 3.3 V 传感器或小型转接板即可完成最小回归：

- UART：USB 串口终端，115200、8-N-1；观察 `tn9k_board_demo` 的启动文本。UART1 测试时保留
  UART0 作为救砖/下载通道，并在 J5.18/J5.19 使用另一只 3.3 V TTL 串口。
- PWM：示波器或 LED+限流电阻接 PWM0；默认约 1 kHz、50% 占空比。PWM1 测试时使用
  J5.12..15、逻辑级负载或经过审查的驱动板，并记录四路相位/占空比与 disable 后低电平。
- TIMER1：先确认未连接 RGB LCD，再向 J5.16/J5.17 输入已知低压 A/B Gray 序列；记录滤波值、
  正反向计数、捕获时间戳、非法跳变和噪声下的误计数。
- GPIO：LED/逻辑分析仪接 GPIO0..11；先从 GPIO0..2 开始，再确认未连接 RGB LCD 后使用 GPIO3..11。
- PULSE0 / FAULT0：分别用经限压的 3.3 V 信号发生器或人工开关验证滤波、边沿、锁存、清除拒绝、
  PWM 拉低和 GPIO 高阻；保持 UART0 连接，先在低风险逻辑负载上试验。
- SPI：MOSI 和 MISO 用短跳线回环，CS/SCK 接逻辑分析仪；用 SDK `SPI0` 传输 API。
- I2C：接一个有已知地址的 3.3 V I2C 目标和外部上拉；先用逻辑分析仪检查 START、
  地址、ACK、STOP，再写目标专用事务。

## 实体板放行清单

在声称“可用开发板”前，逐项记录板 revision、使用的 `.fs` SHA-256、工具版本和结果：

- [ ] USB 上电、冷启动和按键复位各 1000 次；
- [ ] 六个 LED 极性、UART0 与 UART1 TX/RX、27 MHz 时钟的实测；
- [ ] SRAM 下载、断电消失、Flash 下载、断电后重启四种行为；
- [ ] GPIO 高/低/高阻、PWM0/PWM1 周期/占空比/disable 低电平、TIMER1 捕获/正交方向、SPI 回环；
- [ ] GPIO 同步、共享和独立滤波（掩码、2/4/8 样本）/快照，ALARM0 同 tick，PULSE0 边沿/周期，FAULT0 锁存/门控/清除拒绝，
  增强 WDT 的预警/窗口/heartbeat/复位原因；
- [ ] I2C 真正目标的 ACK/NACK、时钟拉伸和断线恢复；
- [ ] 连接外设时电压、地、温升和信号完整性检查。

只有这些记录存在，才可以将相应测试项从“数字仿真/P&R”升级为“板级已验证”。
