# Tang Nano 9K 外露引脚与 OpenMCU 定义

> **结论：**ABI 0.9 发布的 19 根 MCU 信号全部位于 Tang Nano 9K 实物左排 `L1..L19`，均为
> 3.3 V I/O；其中 `L8..L19` 是完整 GPIO0..11。UART0 不在排针上，它通过板载 BL702 和 USB-C
> 对外提供烧录、恢复与日志。右排的 1.8 V、HDMI 共线和当前未实现位置不能冒充可用 MCU GPIO。

本页是“实物孔位”和 OpenMCU 软件名称之间的快速合同。机器可读真相源为
[`spec/tangnano9k-pins.json`](../../spec/tangnano9k-pins.json)，CI 使用
[`scripts/check-tangnano9k-pinmap.py`](../../scripts/check-tangnano9k-pinmap.py)逐项核对 48 个孔位、
CST package pin 和 SDK 物理别名。

## 1. 方向与官方依据

观察方向固定为：**元件面朝上、板载下载器 USB-C 在顶部**。左排从上向下叫 `L1..L24`，对应
原理图 `J5.1..J5.24`；右排从上向下叫 `R1..R24`，对应 `J6.1..J6.24`。PCB 不一定逐孔印出
`Lx/Rx`，所以不要只凭附近文字猜位置。

![Sipeed Tang Nano 9K 官方 Pinmap](assets/sipeed-tang-nano-9k-official-pinmap.png)

核对来源：

- [Sipeed Tang Nano 9K 官方页面与 Pinmap](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/Nano-9K.html)
- [Sipeed 6202 官方原理图](https://dl.sipeed.com/fileList/TANG/Nano%209K/2_Schematic/Tang_Nano_9k_3672_Schematic.pdf)

官方资料明确区分 3.3 V Bank 与右排 Bank 3 的 1.8 V，并警告 HDMI 共线 I/O 带上拉、作为普通
排针 I/O 时可能不按预期工作。因此“孔位物理存在”不等于“OpenMCU 可以安全驱动”。

## 2. 当前可开发的 MCU 引脚

| 实物孔位 | package pin | OpenMCU 名称 | 软件使用方式 | 共线与限制 |
| --- | ---: | --- | --- | --- |
| L1 | 38 | SPI0 CS_N | `OMCU_SPI0` / SDK SPI API | 与 microSD `TF_CS` 共线；不得同时使用 TF 卡。 |
| L2 | 37 | SPI0 MOSI | `OMCU_SPI0` / SDK SPI API | 与 microSD `TF_MOSI` 共线。 |
| L3 | 36 | SPI0 SCK | `OMCU_SPI0` / SDK SPI API | 与 microSD `TF_SCLK` 共线。 |
| L4 | 39 | SPI0 MISO | `OMCU_SPI0` / SDK SPI API | 与 microSD `TF_MISO` 共线。 |
| L5 | 25 | PWM0 | `OMCU_PWM0` / SDK PWM API | 只接 3.3 V 逻辑输入或经过审核的驱动级。 |
| L6 | 26 | I2C0 SCL | `OMCU_I2C0` / SDK I2C API | 真开漏；外部必须提供合适的 3.3 V 上拉。 |
| L7 | 27 | I2C0 SDA | `OMCU_I2C0` / SDK I2C API | 真开漏；外部必须提供合适的 3.3 V 上拉。 |
| L8 | 28 | GPIO0 / PULSE0 IN0 | `OMCU_TN9K_GPIO0` 或 `OMCU_TN9K_L8_GPIO` | 同时镜像 LED0。 |
| L9 | 29 | GPIO1 / PULSE0 IN1 | `OMCU_TN9K_GPIO1` 或 `OMCU_TN9K_L9_GPIO` | 同时镜像 LED1。 |
| L10 | 30 | GPIO2 / PULSE0 IN2 | `OMCU_TN9K_GPIO2` 或 `OMCU_TN9K_L10_GPIO` | 同时镜像 LED2。 |
| L11 | 33 | GPIO3 / FAULT0 | `OMCU_TN9K_GPIO3` 或 `OMCU_TN9K_L11_GPIO` | 与 RGB LCD `DE` 共线；同时镜像 LED3。 |
| L12 | 34 | GPIO4 / PWM1 CH0 | `OMCU_TN9K_GPIO4` 或 `OMCU_TN9K_L12_GPIO` | 与 RGB LCD `VS` 共线；同时镜像 LED4。 |
| L13 | 40 | GPIO5 / PWM1 CH1 | `OMCU_TN9K_GPIO5` 或 `OMCU_TN9K_L13_GPIO` | 与 RGB LCD `HS` 共线；同时镜像 LED5。 |
| L14 | 35 | GPIO6 / PWM1 CH2 | `OMCU_TN9K_GPIO6` 或 `OMCU_TN9K_L14_GPIO` | 与 RGB LCD `CK` 共线。 |
| L15 | 41 | GPIO7 / PWM1 CH3 | `OMCU_TN9K_GPIO7` 或 `OMCU_TN9K_L15_GPIO` | 与 RGB LCD `B7` 共线。 |
| L16 | 42 | GPIO8 / TIMER1 A | `OMCU_TN9K_GPIO8` 或 `OMCU_TN9K_L16_GPIO` | 与 RGB LCD `B6` 共线。 |
| L17 | 51 | GPIO9 / TIMER1 B | `OMCU_TN9K_GPIO9` 或 `OMCU_TN9K_L17_GPIO` | 与 RGB LCD `B5` 共线。 |
| L18 | 53 | GPIO10 / UART1 TX | `OMCU_TN9K_GPIO10` 或 `OMCU_TN9K_L18_GPIO` | 与 RGB LCD `B4` 共线。 |
| L19 | 54 | GPIO11 / UART1 RX | `OMCU_TN9K_GPIO11` 或 `OMCU_TN9K_L19_GPIO` | 与 RGB LCD `B3` 共线。 |

因此，客户写普通 GPIO 程序时只使用一个统一掩码：

```c
#include "omcu_tn9k.h"

_Static_assert(OMCU_TN9K_GPIO_COUNT == 12u, "unexpected board profile");

/* L8 输出高；L19 保持输入。 */
omcu_gpio_set(OMCU_TN9K_L8_GPIO);
omcu_gpio_enable_output(OMCU_TN9K_L8_GPIO);
omcu_gpio_disable_output(OMCU_TN9K_L19_GPIO);
```

不要在应用中写 package pin `28`、`54` 等数字；这些是 FPGA 约束信息，不是 GPIO 寄存器位。

## 3. 左排完整状态

| 左排 | package pin | 电压 | 状态 | 说明 |
| --- | ---: | ---: | --- | --- |
| L1..L7 | 38/37/36/39/25/26/27 | 3.3 V | **公开** | SPI0、PWM0、I2C0。 |
| L8..L19 | 28/29/30/33/34/40/35/41/42/51/53/54 | 3.3 V | **公开** | GPIO0..11 及显式 PINMUX 替代功能。 |
| L20..L22 | 55/56/57 | 3.3 V | **保留** | 实物存在并与 RGB LCD G7/G6/G5 共线，但 ABI 0.9 没有对应 GPIO bit。 |
| L23..L24 | 68/69 | 3.3 V | **禁用** | 同时是 HDMI 时钟 N/P；官方警告 HDMI 路径带上拉。 |

`L20..L22` 的“保留”不是接线许可：当前 `.fs` 没有把它们接入 MCU 寄存器，软件无法控制。
任何后续扩展都必须同时修改 RTL、CST、SDK/ABI，重新完成精确目标 P&R，并做实体板 HIL。

## 4. 右排完整状态

| 右排 | package pin / 电源 | 电压 | 状态 | 说明 |
| --- | --- | ---: | --- | --- |
| R1 | 63 | 3.3 V | **保留** | RGB 初始化/触摸共线，当前 MCU 未实现。 |
| R2..R9 | 86..79 | **1.8 V** | **禁用** | Bank 3；绝不能按 3.3 V MCU GPIO 接线。 |
| R10..R11 | 77/76 | 3.3 V | **保留** | 与板载 1.14 英寸 SPI LCD MOSI/CLK 共线，当前 MCU 未实现。 |
| R12..R17 | 75..70 | 3.3 V | **禁用** | HDMI D2/D1/D0 差分路径且带上拉，不作为可靠普通 GPIO。 |
| R18 | +5V | 5 V | **电源** | 不是 GPIO；不要接 USB-TTL 的 VCC，也不要反向给板供电。 |
| R19..R20 | 48/49 | 3.3 V | **保留** | SPI LCD CS/RS，共线且当前 MCU 未实现。 |
| R21..R22 | 31/32 | 3.3 V | **保留** | RGB 初始化/触摸共线，当前 MCU 未实现。 |
| R23 | GND | 0 V | **地** | 外接 USB-TTL/模块必须共地。 |
| R24 | +3V3 | 3.3 V | **电源** | 不是 GPIO；外部供电和负载能力须另做板级审核。 |

右排“保留”脚在原理图上确实是 3.3 V FPGA I/O，但当前 MCU 位流没有 MMIO 映射；“禁用”脚还存在
1.8 V 或 HDMI 板级电气冲突。两者都不能在应用代码中自行占用。

## 5. UART0 与 UART1 不要混淆

- **UART0**：FPGA package 17/18 已经在 PCB 内连接到 BL702 USB-UART。Mac/PC 通过板载 USB-C
  使用它，不需要、也不应再把外置 USB-TTL TX 并接到 UART0 RX。UART0 是 `.omcu` 烧录和救砖通道。
- **UART1**：通过 PINMUX 使用 L18/L19。外置 3.3 V USB-TTL 的 `RXD → L18`、`TXD → L19`、
  `GND → R23`，电源脚不连接。

## 6. 自动核对

修改板级引脚、CST 或 SDK 物理别名后必须运行：

```sh
python3 ./scripts/check-tangnano9k-pinmap.py
pwsh ./scripts/check-tangnano9k-project.ps1 -McuMode
```

第一项保证 2×24 全部孔位只有一个定义，并拒绝把 1.8 V/HDMI 脚发布为 3.3 V MCU 信号；第二项保证
产品工程仍包含完整 RTL 和已要求的 CST 端口。数字合同通过后，仍要按
[MCU 外设实体板验收](mcu-peripheral-qualification.md)断电接线并保留 HIL 日志。
