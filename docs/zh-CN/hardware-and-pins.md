# Tang Nano 9K 硬件与引脚

## 板级边界

目标板是 `GW1NR-LV9QN88PC6/I5`（GW1N-9C）。Sipeed 的 Tang Nano 9K 产品资料列出
GW1NR-9、6 个 LED、2 个按键、32 Mbit SPI Flash、64 Mbit PSRAM、USB 下载器和两组
扩展 I/O；OpenMCU 使用其中 FPGA 逻辑和已约束的 I/O，不会把板载 PSRAM/Flash
自动宣称为 MCU 的已验证程序存储器。

本仓库的约束文件是
[`rtl/platform/tangnano9k/project/omcu_tn9k_bringup.cst`](../../rtl/platform/tangnano9k/project/omcu_tn9k_bringup.cst)。
下表的 package pad 已通过 P&R 解析；**尚未在当前实体板上验证**。生产前必须对照
你手中的板卡 revision 原理图、测量电平，并执行后文的板级清单。

| OpenMCU 功能 | 顶层端口/逻辑 GPIO | package pad | 用途和注意事项 |
| --- | --- | ---: | --- |
| 时钟 | `clk_27m_i` | 52 | 板载 27 MHz，SDC 约束为 27 MHz。 |
| 外部复位 | `resetn_i` | 4 | 低有效；顶层异步断言、同步释放。 |
| UART0 TX/RX | `uart_tx_o` / `uart_rx_i` | 17 / 18 | 3.3 V 逻辑，默认 SDK 115200 8-N-1。 |
| LED0..5 | GPIO0[0..5] / `led_n_o[0..5]` | 10,11,13,14,15,16 | 板上 LED 为低电平点亮；SDK 逻辑 GPIO 为高表示“点亮”。 |
| SPI0 CS/MOSI/SCK/MISO | `spi0_*` | 38/37/36/39 | 来自 J5/TF-card 信号组；SPI0 使用时不得同时插入或访问 microSD。 |
| I2C0 SCL/SDA | `i2c0_scl_io` / `i2c0_sda_io` | 26 / 27 | 真正开漏；外部必须提供合适的 3.3 V 上拉。 |
| PWM0 | `pwm0_o` | 25 | 单路边沿对齐 PWM。 |
| 扩展 GPIO | GPIO0[6..8] / `gpio_io[0..2]` | 28 / 29 / 30 | 可输入、输出或高阻；默认高阻。 |

`GPIO0[0..5]` 与 LED 专用映射不可同时作为外部数字引脚使用。`GPIO0[6..8]` 才是当前
公开的三路通用 I/O。它们在顶层中真正遵守 `OE`：软件清掉 `OE` 后，FPGA pad 会释放为
高阻，而不是把“1”推到外部总线。

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

## 建议的首块外设实验板

用一个 3.3 V 传感器或小型转接板即可完成最小回归：

- UART：USB 串口终端，115200、8-N-1；观察 `tn9k_board_demo` 的启动文本。
- PWM：示波器或 LED+限流电阻接 PWM0；默认约 1 kHz、50% 占空比。
- GPIO：LED/逻辑分析仪接 GPIO0..2；示例每约 250 ms 翻转。
- SPI：MOSI 和 MISO 用短跳线回环，CS/SCK 接逻辑分析仪；用 SDK `SPI0` 传输 API。
- I2C：接一个有已知地址的 3.3 V I2C 目标和外部上拉；先用逻辑分析仪检查 START、
  地址、ACK、STOP，再写目标专用事务。

## 实体板放行清单

在声称“可用开发板”前，逐项记录板 revision、使用的 `.fs` SHA-256、工具版本和结果：

- [ ] USB 上电、冷启动和按键复位各 1000 次；
- [ ] 六个 LED 极性、UART TX/RX、27 MHz 时钟的实测；
- [ ] SRAM 下载、断电消失、Flash 下载、断电后重启四种行为；
- [ ] GPIO 高/低/高阻、PWM 周期/占空比、SPI 回环；
- [ ] I2C 真正目标的 ACK/NACK、时钟拉伸和断线恢复；
- [ ] 连接外设时电压、地、温升和信号完整性检查。

只有这些记录存在，才可以将相应测试项从“数字仿真/P&R”升级为“板级已验证”。
