# MCU 外设实体板验收

本文定义 OpenMCU-TN9K 从“RTL/SDK 可用”提升到“特定实体板与接线可复现”的验收方法。它不把
寄存器仿真、P&R 或空载读回冒充外部电气验证，也不把一块板的通过结果外推成量产资格。

Tang Nano 9K 的器件、接口与 2×24 排针来自 [Sipeed 官方板卡页](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/Nano-9K.html)；
J5 网络到 FPGA pad 的映射以 2022-10-23 的
[官方 6202 原理图](https://dl.sipeed.com/fileList/TANG/Nano%209K/2_Schematic/Tang_Nano_9k_3672_Schematic.pdf)
第 3/5 张图为依据，并与本仓库 `omcu_tn9k_bringup.cst` 双重核对。官方资料同时要求 GPIO 不得超过
原理图标注电压，并提醒静电、短路和复用 I/O 风险。

> **实物定位约定：**`J5.1..24` 是原理图内部连接器编号，PCB 通常不会把这些编号逐针丝印出来。
> 本文面向接线时改用 `L1..L24`：开发板**元件面朝上、USB-C 在顶部**，左侧暴露排针从上向下计数。
> `Lx` 与原理图 `J5.x` 一一对应，但 `Lx` 是本验收文档的物理位置名，不冒充板上丝印。

![Sipeed Tang Nano 9K 官方 Pinmap](assets/sipeed-tang-nano-9k-official-pinmap.png)

图源为 Sipeed 官方 Wiki，随图保留的来源与 MIT 许可说明见 [`assets/README.md`](assets/README.md)。

官方图在每个暴露孔旁标的是 **FPGA package pin**，左排从上向下依次为
`38,37,36,39,25,26,27,28,29,30,33,34,40,35,41,42,51,53,54,55,56,57,68,69`。
接线必须同时核对“左排位置”和“官方 FPGA 数字”；若手中板卡外观、方向或 revision 不匹配，停止接线并拍照复核。

## 1. 当前证据结论

2026-08-27，在一块通过 USB-C 连接 macOS、未插 TF/RGB LCD、J5/J6 无外接负载的 Tang Nano 9K
上，`omcu_mcu_selftest` 完成 **24/24**：

- 实际 WDT 整机复位，`RESET_CAUSE=WATCHDOG`，保留计数 `0 → 1`；
- CPU 身份/ABI/全部 feature、RV32IM 乘除、16 KiB SRAM 双图样；
- SYSCTRL tick、IRQCTRL force/clear、TIMER0、ALARM0、TIMER1 compare、WDT supervisor；
- 12 路 GPIO 输出经最终 pad 输入缓冲回读，四路 PWM1 最终 pad 高/低回读，UART1 TX pad；
- SPI0 完整字节引擎与空载上拉 MISO，I2C0 空载 START/STOP；
- UART0 应用层双向 `PING/PONG`。

测试镜像 SHA-256 为
`185095439102a5328674a73a72ab6f16ea38bc4a8ebe11bb29900531b05fa587`，对应 FPGA `.fs` SHA-256 为
`3c2b9943bc93bcb8cb42f52006d8cf4b34e0a3ffb310b7bfc9b2aaa278386099`。这证明当前单板的核心 MCU、
复位、存储、UART0 和若干无夹具 pad 路径工作；它**没有**证明 UART1 RX、SPI 外部回环、I2C 目标器件、
PWM0/1 波形精度、TIMER1 外部捕获、PULSE/FAULT 外部输入或外置器件驱动已通过。

UART0 不在左排跳线中：FPGA package pad 17/18 已由 Tang Nano 9K PCB 接到板载 BL702 USB-UART，
测试主机通过同一 USB-C 枚举的串口访问它，不需要额外连接 UART0。

同日安装第 3 节六根跳线后，`omcu_mcu_loopback_selftest` 又完成 **8/8**，实际闭环 UART1 RX、
SPI0、TIMER1 encoder/capture、PWM0/1、PULSE0 和 FAULT0。修正后回环镜像 SHA-256 为
`95e3a8e2c41cb4e3fbce4fb27184bd78b4707109f010c70605f8a976a1b80dde`，原始成功转录 SHA-256 为
`60e5262a528f1ee112d6f3da360fc75e2a8e0e15e53fc17fb1b9101500dbd752`，对应最终 FPGA `.fs`
SHA-256 `cdb0217f7c8a4caf03869aa6f9b08e957ea5b1c89b4289d43b783878f7152056`。逐项记录、首轮 7/8 的
测试固件根因及旧版 `BEGIN` 超时的定位/修复见[2026-08-27 六线回环实板记录](evidence/tangnano9k-loopback-2026-08-27.md)。
这仍不证明 I2C 目标模块、模拟/时序精度、最大速率、长线/负载或量产可靠性。

同日拆除 `L18 → L19` 回环线并接入外置 3.3 V FT232R（`RXD → L18`、`TXD → L19`、
`GND → R23`）后，UART1 又完成四轮全字节域和 32 × 2,048 B 连续块测试，总计 65,536 B，
发送/回传 SHA-256 完全相同。首版阻塞式示例在连续 2,048 B 中丢失 31 B；根因是等待 TX 时未及时
清空单字节 RX holding register，改为 256 B 软件队列并独立轮询 RX/TX 后，同一负载和最终压力测试
均无错。完整记录见[UART1 / USB-TTL 实板记录](evidence/tangnano9k-uart1-usbttl-2026-08-27.md)。

## 2. 无夹具核心自检

确认没有 TF 卡、RGB LCD 或 J5/J6 外接负载，再构建：

```sh
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
python3 ./tools/omcu_selftest.py \
  --port /dev/cu.usbserial-XXXX \
  --image ./build/sdk/omcu_mcu_selftest.omcu \
  --log ./build/hil/core-selftest.log
```

Windows 把串口改为 `COM5` 并使用 `python`。工具开始寻找 Bootloader 后按一次复位；固件会故意再触发
一次 WDT 复位，第二次启动完成测试。唯一通过条件是主机逐项收到 24 个预期 `PASS`、完成
`READY UART0_RX → PING → PONG`，最后收到：

```text
RESULT PASS pass=24 fail=0
```

若左侧暴露排针上接有任何目标电路，不运行这项测试，因为 GPIO/PWM/SPI/UART1 会短暂改变方向或电平。

## 3. 固定无源回环夹具

### 3.1 断电接线

完全断开 USB 电源后，用短跳线连接下表。不要插 TF 卡或 RGB LCD，不要给任何排针信号注入 5 V。

![OpenMCU-TN9K 六线实物回环图](assets/openmcu-tn9k-loopback-physical-pinmap.png)

| 跳线（元件面、USB-C 在顶部） | 官方 FPGA 数字 | OpenMCU 路径 | 验证目的 |
| --- | --- | --- | --- |
| 左排第 2 孔 `L2` → 第 4 孔 `L4` | `37 → 39` | SPI0 MOSI → MISO | 7 个位图样的 mode-0 实体回环。 |
| 左排第 18 孔 `L18` → 第 19 孔 `L19` | `53 → 54` | UART1 TX → RX | 8 个字节、115200 8N1 实体回环和错误状态。 |
| 左排第 12 孔 `L12` → 第 16 孔 `L16` | `34 → 42` | GPIO4 / PWM1 CH0 → TIMER1 A | GPIO 线束、编码器 A、PWM1 捕获。 |
| 左排第 13 孔 `L13` → 第 17 孔 `L17` | `40 → 51` | GPIO5 / PWM1 CH1 → TIMER1 B | GPIO 线束、编码器 B、PWM1 捕获。 |
| 左排第 14 孔 `L14` → 第 11 孔 `L11` | `35 → 33` | GPIO6 / PWM1 CH2 → FAULT0 | active-low 故障、GPIO 全高阻门控和安全清除。 |
| 左排第 5 孔 `L5` → 第 8 孔 `L8` | `25 → 28` | PWM0 → PULSE0 input 0 | PWM0 实际输出、PULSE 边沿计数和周期。 |

左排 `L1/L2/L3/L4`（原理图 J5.1..4）分别是 SPI0 `CS/MOSI/SCLK/MISO`；`L5` 是 PWM0；
`L6/L7` 是 I2C0 `SCL/SDA`；`L8..L19` 是 GPIO0..11。六根测试线所用的十二个孔全部在官方
Pinmap 中真实暴露且属于 3.3 V Bank。`L2/L4` 同时接到空置 TF 卡座，`L11..L19` 同时接到空置
RGB LCD 连接器，因此必须在未插 TF 卡/RGB LCD 时测试。

### 3.2 自动验收

```sh
python3 ./tools/omcu_selftest.py \
  --profile loopback \
  --port /dev/cu.usbserial-XXXX \
  --image ./build/sdk/omcu_mcu_loopback_selftest.omcu \
  --log ./build/hil/loopback-selftest.log
```

测试按安全顺序复用跳线：先 GPIO 线束，再 UART1/SPI，随后 GPIO bit-bang 正反 Gray 序列验证
TIMER1 capture/encoder；再让 PWM1 CH0/1 经实体跳线返回 TIMER1 检查约 1024 tick 周期；PWM0 经
PULSE0 检查约 2700 tick 周期；最后由 GPIO6 产生 active-low FAULT，硬件把所有 GPIO 强制高阻，
内部 pull-up 令故障源恢复 inactive，软件先把源锁存改回高电平后才清故障。

必须逐项收到以下 8 个结果并以 `RESULT PASS pass=8 fail=0` 结束：

```text
PASS HARDWARE_CAPABILITIES
PASS HARNESS_GPIO
PASS UART1_LOOPBACK
PASS SPI0_LOOPBACK
PASS TIMER1_ENCODER_LOOPBACK
PASS PWM1_TIMER1_LOOPBACK
PASS PWM0_PULSE0_LOOPBACK
PASS FAULT0_GPIO_GATE_LOOPBACK
```

修正后镜像已通过交叉编译和 `.omcu` 校验，SHA-256 为
`95e3a8e2c41cb4e3fbce4fb27184bd78b4707109f010c70605f8a976a1b80dde`。2026-08-27 当前单板安装上述
跳线后实测 **8/8 通过**。早期恢复模板应用时出现的 `BEGIN` 无 ACK 已定位为 HELLO 响应后的冗余
Flash 扫描导致单字节 UART RX overrun；最终 Boot ROM
修复后，精确最终 `.fs` 已连续完成 A→B→A 和固化后空白→A→B。实体回环再次得到 8/8。
本结论只适用于[记录中的板、工件和接线](evidence/tangnano9k-loopback-2026-08-27.md)，不能预填到其他板。

## 4. I2C 与实际目标器件

I2C 无法用一根被动跳线验证 ACK、NACK、读写和 clock stretching。至少接一个已知 3.3 V 模块：

| Tang 实物位置 | 官方标识 | 模块引脚 | 要求 |
| --- | --- | --- | --- |
| 左排第 6 孔 `L6` | FPGA `26` | SCL | 开漏；外部上拉到 3.3 V。 |
| 左排第 7 孔 `L7` | FPGA `27` | SDA | 开漏；外部上拉到 3.3 V。 |
| 右排最底孔 `R24` | `3V3` | VCC | 仅 3.3 V 模块。 |
| 右排倒数第 2 孔 `R23` | `GND` | GND | 必须共地。 |

SCL/SDA 各用 4.7 kΩ 到 3.3 V 作为起点；若模块已带上拉，不要盲目并联过低阻值。最低验收应包含：

- [TI TMP102](https://www.ti.com/product/TMP102)（A0 接地时 `0x48`）连续读取温度，值域合理且无总线错误；
- [ADI DS3231](https://www.analog.com/en/products/ds3231.html) 读写时间并跨秒递增，或
  [Microchip AT24C32D](https://www.microchip.com/en-us/product/AT24C32D) 对测试地址执行写入、轮询完成、读回和恢复原值；
- 人为访问空地址得到 NACK 且控制器可发 STOP 后继续下一次事务；
- 若目标支持 clock stretching，以逻辑分析仪确认 SCL 释放等待；
- 100 kHz 起测，再按线长、总线电容和上拉实测决定是否提速。

`omcu_external_peripherals` 和 `OpenMCU::device_drivers` 已提供 DS3231、AT24Cxx、TMP102、MCP3008、
MCP4921 与 W5500 API，但“驱动能编译”不算目标模块 HIL。

## 5. 仪器与目标模块门禁

无源回环之后仍需用示波器或逻辑分析仪记录：

| 对象 | 最低量测 / 目标验收 |
| --- | --- |
| UART0/1 | 115200 8N1 位宽、空闲电平、连续数据无 framing/overrun；按预计线长重复。 |
| SPI0 | 左排 `L1/L2/L3/L4`，官方 FPGA `38/37/36/39`，依次为 CS/MOSI/SCLK/MISO；mode 0、约 1 MHz、首尾边沿和多字节 CS hold。 |
| PWM0/1 | 频率、四路 duty、0%/100%、invert、disable 确定低；连接功率级前另做死区/失效安全设计。 |
| GPIO/TIMER1/PULSE | VIH/VIL、输出驱动、输入滤波边界、编码器合法/非法序列、最大可靠输入频率和线缆噪声。 |
| FAULT/WDT | 外部安全逻辑负载上确认门控先于软件响应、clear 拒绝、预警/窗口/heartbeat 和真实复位。 |
| MCP3008/MCP4921 | 已知电压输入与万用表/示波器输出误差；不要只验证 SPI 返回字节。 |
| W5500 | 按 [WIZnet 官方资料](https://docs.wiznet.io/Product/Chip/Ethernet/W5500/datasheet)检查 VERSIONR、静态网络配置、ARP/ICMP、TCP 双向数据、断网/重连和长时间传输。 |

每项日志必须记录板卡编号/revision、跳线或模块型号、供电、位流和 `.omcu` SHA-256、工具版本、
温度/线长/速率、原始串口与仪器截图。至少两块板和预期环境边界重复后，才把具体外设标为产品合格。

## 6. 证据等级

| 状态 | 可以声称 | 不可以声称 |
| --- | --- | --- |
| RTL/SDK PASS | 数字合同与编译固件行为通过。 | 实际 pin、电平或外部模块可靠。 |
| 无夹具 24/24 PASS | 当前单板核心 MCU、UART0、WDT、SRAM及列出的 pad 自读路径通过。 | UART1 RX、外部 SPI/I2C/PWM/输入路径已经闭环。 |
| 固定回环 8/8 PASS | 当前板与当前跳线下的数字外设闭环通过。 | 模拟精度、功率负载、长线、EMC、目标器件协议或量产寿命。 |
| UART1 USB-TTL PASS | 当前板、适配器、短线和 115200 8N1 下，L18/L19 全字节与 64 KiB 连续块无错。 | 最大波特率、长线、不同适配器、仪器波形或多板一致性。 |
| 目标模块 + 仪器 PASS | 当前模块、速率、电气和环境矩阵通过。 | 未测模块/环境、多板一致性或认证等级。 |

最终发布签核还必须加入反复冷启动、A/B 各阶段断电、擦写次数、温压边界、多板、ESD/EMC 与应用级
故障恢复；CRC32 也不等于签名安全启动。
