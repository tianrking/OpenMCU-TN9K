# 外设、SDK 与应用开发

> **主规格书入口：**完整的引脚、复用、寄存器语义、IRQ、位宽和电气边界见
> [《OpenMCU-TN9K 外设与引脚完整规格书》](peripheral-pin-specification.md)。
> 本页保留面向 C 应用的 SDK API、用法和示例说明。

## 稳定地址空间

| 基址 | 外设 | Tang 顶层连接 |
| ---: | --- | --- |
| `0x2000_0000` | User Flash 窗口 | GW1NR 独立 User Flash；由启动器管理 A/B 应用槽 |
| `0x4000_0000` | GPIO0 | LED0..5、12 路扩展 GPIO0..11（GPIO3..11 与 RGB LCD 共线） |
| `0x4000_1000` | UART0 | package pad 17/18 |
| `0x4000_2000` | TIMER0 | 片内计数器 |
| `0x4000_3000` | SPI0 | CS/MOSI/SCK/MISO |
| `0x4000_4000` | I2C0 | 开漏 SCL/SDA |
| `0x4000_5000` | WDT0 | 连接 Tang 顶层复位序列器 |
| `0x4000_6000` | PWM0 | 一路 PWM pad |
| `0x4000_7000` | IRQCTRL | 十一个外设来源的 sticky、屏蔽、强制与优先级视图 |
| `0x4000_8000` | UART1 | 无 FIFO 的第二路 UART；Tang 上经 PINMUX 连接 GPIO10/11（J5.18/J5.19） |
| `0x4000_9000` | TIMER1 | 两路同步滤波捕获、比较定时器和正交编码器；Tang 上经 PINMUX 连接 GPIO8/9（J5.16/J5.17） |
| `0x4000_A000` | PWM1 | 四路共享计数器 PWM；Tang 上经 PINMUX 连接 GPIO4..7（J5.12..15） |
| `0x4000_B000` | PINMUX | 显式选择已审查的扩展 pad 替代功能；复位时所有可用 pad 归 GPIO |
| `0x4000_C000` | ALARM0 | 两路并行硬件 compare / periodic alarm |
| `0x4000_D000` | PULSE0 | GPIO0..2 中单选一路的低速边沿计数 / 周期测量 |
| `0x4000_E000` | FAULT0 | GPIO3 故障锁存、PWM/GPIO 门控和共享快照 |
| `0x4000_F000` | SYSCTRL | `OMCU` ID、ABI、功能位、内存容量、复位诊断与产品 Bootloader 请求 |

所有寄存器是 32-bit little-endian；SDK 不建议使用裸常数地址。包含 `omcu.h` 后可使用
`OMCU_GPIO0`、`OMCU_UART0` 等寄存器结构和封装函数。包含 `omcu_tn9k.h` 后可使用
固定时钟、LED 与扩展 GPIO 逻辑掩码。

## 启动时应做的 ABI 检查

```c
#include "omcu_tn9k.h"

const uint32_t required = OMCU_FEATURE_GPIO0 | OMCU_FEATURE_UART0 |
                          OMCU_FEATURE_SPI0 | OMCU_FEATURE_I2C0 |
                          OMCU_FEATURE_WDT0 | OMCU_FEATURE_PWM0 |
                          OMCU_FEATURE_USER_FLASH;

if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
    !omcu_hw_has_feature(required)) {
  for (;;) { }
}
```

不要仅凭 bitstream 文件名判断硬件版本。`SYSCTRL` 会报告 ABI 主版本、功能位和实际
ROM/SRAM KiB；如果 ABI 主版本不同，应用应拒绝运行。

`OMCU_USER_FLASH_BASE` 是启动器的底层存储窗口，不是应用的通用文件系统或应用配置区。正常客户应用不应直接擦写该区域：启动器需要保持 A/B 槽、镜像头、状态字和回退语义一致。应用固件请使用 `tools/omcu_flash.py` 更新，详见 [独立 MCU 固件开发与升级](mcu-firmware-update.md)。

## 常见任务

### GPIO 和 LED

```c
omcu_gpio_enable_output(OMCU_TN9K_LED0);
omcu_gpio_set(OMCU_TN9K_LED0);       /* LED0 点亮：顶层处理低有效极性 */
omcu_gpio_toggle(OMCU_TN9K_GPIO6);  /* J5.14 上的 GPIO6 切换 */
omcu_gpio_disable_output(OMCU_TN9K_GPIO6); /* 释放为高阻输入 */
```

`OMCU_FEATURE_GPIO_EXPANSION` 表示产品顶层已提供 12 路档案；它不是这些 pad 已通过外设
电气 HIL 的声明。GPIO3..11 位于 J5 的 RGB-LCD 共线区域，不能与显示器并用，完整映射和
电压边界见[硬件与引脚](hardware-and-pins.md)。

### 中断与 IRQCTRL

IRQCTRL 已把 GPIO0/UART0/TIMER0/SPI0/I2C0/WDT0/UART1/TIMER1/ALARM0/PULSE0/FAULT0 分别映射为 CPU bit 8..18；应用程序
不必写 Verilog，也不应直接发射 PicoRV32 自定义指令。定义一个 strong
`omcu_irq_dispatch(uint32_t pending)`，先清外设来源、再清 IRQCTRL：

```c
void omcu_irq_dispatch(uint32_t pending) {
  if ((pending & OMCU_IRQ_TIMER0) != 0u) {
    OMCU_TIMER0->ctrl = 0u;
    OMCU_TIMER0->status = OMCU_TIMER_STATUS_PENDING;
    omcu_irqctrl_ack(OMCU_IRQ_TIMER0);
  }
}

omcu_irqctrl_set_enable(0u);
omcu_irqctrl_ack(OMCU_IRQ_EXTERNAL_MASK);
omcu_timer_start_periodic(0u, 27000u);
omcu_irqctrl_set_enable(OMCU_IRQ_TIMER0);
(void)omcu_irq_global_enable();
```

`pending` 可同时包含多个 bit；必须处理全部已使能来源，或禁用并确认不处理的来源。
先清 IRQCTRL 而外设状态仍为有效时，硬件会重新捕获该事件，这是防丢中断的有意行为。
固定向量、现场保护、非嵌套限制和每个来源的应答细节见
[中断开发约定](interrupts.md)。这条路径是 PicoRV32 自定义 ABI，不是标准 RISC-V
machine-mode/CSR/PLIC API。

### UART0

```c
omcu_uart0_init(omcu_tn9k_uart_bauddiv(115200u), false);
omcu_uart0_write_byte('O');
```

顶层系统时钟为 27 MHz；115200 的除数为 233。启用 `enable_rx_irq=true` 后，读取
`DATA` 会消耗 RX 字节；随后在中断函数中确认 `OMCU_IRQ_UART0`。串口 RX、错误状态和
IRQ RTL 有覆盖，但需要实体板串口回归才能承诺电气兼容性。

### UART1：给客户设备的第二路串口

UART1 使用与 UART0 相同的 8-N-1、可编程分频、单字节 RX 寄存器和 RX IRQ 合同，但没有
FIFO、流控、DMA 或自动 RS-485 方向。它仅在 `OMCU_FEATURE_UART1` 和
`OMCU_FEATURE_PINMUX` 都存在时可用，RX 中断为 `OMCU_IRQ_UART1`（CPU bit 14）。Tang Nano
9K 的安全接入方式是：

```c
if (omcu_tn9k_uart1_init(omcu_tn9k_uart_bauddiv(115200u), true)) {
  omcu_uart1_write_byte('O');
}
```

这会让 `PINMUX.CTRL` 的 bit 0 取得 GPIO10（TX）/GPIO11（RX）的 pad 所有权。不要一面开启
UART1，一面再将同一 GPIO 配成推挽输出；不要在这两根 RGB-LCD 共线引脚接显示器。UART1 的
RTL、MMIO、IRQCTRL bit 14 和 Tang pad mux 都有数字仿真覆盖；真实 3.3 V 串口电平、波特率和
复用冲突仍待 HIL。

### SPI0

SPI0 是 8-bit、MSB-first、mode 0 主机。默认每次 `START` 自动拉低一个 CS 并传输一个
字节；当前 ABI 的 `CTRL.CS_HOLD` 使多个字节 `START` 可以共用同一次低有效 CS：

```c
uint8_t rx;
omcu_spi0_init(13u, false);  /* 约 1 MHz：27 MHz / (2 * (13 + 1)) */
if (!omcu_spi0_transfer(0x9fu, &rx)) {
  /* 处理未使能或异常状态 */
}
```

`omcu_spi0_set_cs_hold(true)` 必须在第一个字节前调用；最后一字节完成且 `BUSY=0` 后调用
`omcu_spi0_set_cs_hold(false)` 释放 CS。`omcu_bus.h` 已把这条约束封装为
`omcu_spi0_frame_begin()` / `omcu_spi0_frame_transfer()` / `omcu_spi0_frame_end()`，W5500、
MCP3008、MCP4921 等多字节帧应使用它，不能靠多次旧式 `omcu_spi0_transfer()` 拼接。

它不是 QSPI/XIP 控制器，没有 FIFO、DMA 或多片选。不要把 TF-card 信号组同时用于
microSD 和外接 SPI。

### I2C0

I2C0 是单主机、开漏、逐字节引擎，支持 START / repeated START / STOP / 写字节 /
读字节和时钟拉伸等待：

```c
omcu_i2c0_init(134u, false); /* 约 100 kHz */
if (!omcu_i2c0_start() ||
    !omcu_i2c0_write_byte((0x50u << 1) | 0u) ||
    !omcu_i2c0_stop()) {
  /* 检查 ACK_ERROR 或 COMMAND_ERROR，并按设备协议恢复 */
}
```

没有 DMA、FIFO、仲裁丢失恢复、总线恢复或自动超时。每个产品必须对目标 I2C 器件实现
外层超时和异常恢复；SCL/SDA 外部上拉是硬性要求。

### P0：外置 ADC、DAC、RTC、EEPROM、传感器与 W5500

`omcu_bus.h` 提供带 `spin_limit` 的 I2C/SPI 事务；它避免设备断线时无限卡住，但该参数是
CPU 轮询上限，不是精确毫秒计时器。`omcu_devices.h` 提供以下已实现的驱动：

| 器件 / 类别 | API | 连接与边界 |
| --- | --- | --- |
| DS3231 RTC | `omcu_ds3231_read_time()` / `omcu_ds3231_write_time()` | I2C，默认 `0x68`。 |
| AT24Cxx EEPROM | `omcu_at24cxx_read()` / `omcu_at24cxx_write()` | I2C；调用者指定 1/2 字节地址、页大小与 ACK 轮询次数。 |
| TMP102 温度传感器 | `omcu_tmp102_read_temperature_milli_c()` | I2C，默认 `0x48`，返回毫摄氏度。 |
| MCP3008 ADC | `omcu_mcp3008_read_channel()` | SPI mode 0，10-bit，使用连续 CS 帧。 |
| MCP4921 DAC | `omcu_mcp4921_write()` | SPI mode 0，12-bit，使用连续 CS 帧。 |
| W5500 以太网控制器 | `omcu_w5500_initialize()`、socket API | SPI mode 0；W5500 自带网络协议硬件，不是 FPGA 内 MAC/PHY。 |

W5500 驱动包含公共寄存器初始化、版本核验、TCP/UDP socket 打开、TCP 连接、环形 TX/RX
缓冲收发。应用必须提供静态 MAC/IP 或自行在上层实现 DHCP；不得把它描述成已经有 FPGA
以太网 MAC/PHY。模块 IRQ 可接一根已通过电压/HIL 验收的 GPIO，并复用 GPIO0 边沿中断；
没有接 IRQ 时可轮询 W5500 socket 状态。完整可编译模板是
`omcu_external_peripherals`。

所有 P0 驱动仅完成源码/编译与 SPI CS 连续帧 RTL 验证。外设的真实 ACK、地址、W5500 链路、
网络收发、电平、TF 互斥和掉电恢复仍必须逐个记录 HIL，未完成前不能宣称板级已支持。

### PWM0、PWM1 与 WDT0

```c
omcu_pwm0_configure(26u, 999u, 500u, false); /* 约 1 kHz，50% */
omcu_wdt0_start(27000000u, true, false);     /* 约 1 s；应用循环需喂狗 */
omcu_wdt0_feed();
```

PWM 为单通道边沿对齐输出，`PERIOD` 为包含端点的 top 值。看门狗超时的复位请求已经
在 Tang 顶层仿真中验证会重启 SoC；实际板上复位行为仍需记录。

PWM1 由 `OMCU_FEATURE_PWM1` 和 `OMCU_FEATURE_PINMUX` 共同声明，地址为
`0x4000_A000`。四个 `DUTY` 寄存器共享 `PRESCALE`、**16-bit** `PERIOD` 和 `COUNT`，因此不会占用
大 FIFO 或 BSRAM，也不会产生可独立相移的通道。`PERIOD`、`DUTY0..3` 和 `COUNT` 的有效范围均为
0..65535，SDK 以 `uint16_t` 表达，MMIO 写入高 16 bit 会被忽略。默认/disable 时输出均为低；
`CTRL` bit 4..7 分别反相 CH0..3。Tang 的推荐调用是：

```c
(void)omcu_tn9k_pwm1_configure(26u, 999u,
                                250u, 500u, 750u, 1000u,
                                0u); /* GPIO4..7 -> PWM1 CH0..3 */
```

若需要在运行中改 duty，直接写 `OMCU_PWM1->duty0` 到 `duty3`；硬件不会替客户实现四路
影子寄存器的原子更新。不要将 PWM1 描述为互补、死区、故障刹车或高压栅极驱动器；它们不在
当前合同内。首次实板必须测量每路频率、相位、占空比、disable 低电平和 RGB-LCD 共线边界。

### TIMER1：滤波输入捕获与正交编码器

TIMER1 由 `OMCU_FEATURE_TIMER1` 与 `OMCU_FEATURE_PINMUX` 共同声明，地址为
`0x4000_9000`。它使用 16-bit 分频、**16-bit** 比较/计数/时间戳和单次/自动重装行为，同时增加 A/B
两路输入。每路严格经过两级同步器和 8-bit `FILTER` 连续稳定样本滤波后，才会触发选定上升/下降沿的
`CAPTURE_A` / `CAPTURE_B` 时间戳，或送入正交 Gray 解码器。`FILTER=N`（0..255）需要 `N+1` 个连续的
不一致同步样本才接受新电平；改写该寄存器会清掉正在累积的滤波计数。`ENCODER` 是低 16-bit 有符号
二补码位置，读取时符号扩展到 `int32_t`；SDK 配置 API 用 `uint16_t` compare 和 `uint8_t` filter，避免
对未实现的高位产生错误预期。

```c
const uint32_t ctrl = OMCU_TIMER1_CTRL_ENABLE |
                      OMCU_TIMER1_CTRL_CAPTURE_A_ENABLE |
                      OMCU_TIMER1_CTRL_CAPTURE_B_ENABLE |
                      OMCU_TIMER1_CTRL_QUADRATURE_ENABLE;

if (omcu_tn9k_timer1_configure(0u, UINT16_MAX, 4u, ctrl)) {
  int32_t position = omcu_timer1_encoder_position();
  omcu_timer1_clear_status(OMCU_TIMER1_STATUS_ENCODER_ILLEGAL);
}
```

`STATUS` 的 compare、capture A、capture B、encoder step 和 illegal 位均为 W1C 事件；只有
`CTRL.IRQ_ENABLE=1` 时任一事件才会驱动 `OMCU_IRQ_TIMER1`（CPU bit 15）。`STATUS.INPUT_A/B`
是滤波后的观察值，`STATUS.ENCODER_DIRECTION` 表示最近一次有效步的方向。正向定义为
`00 -> 01 -> 11 -> 10 -> 00`；`CTRL.QUADRATURE_REVERSE` 只翻转位置方向。它没有 DMA、FIFO、
边沿排队、速度计算或异步高速计数能力；外部信号必须满足同步/滤波时序，且 GPIO8/9 与 RGB LCD
共线。RTL 和编译固件仿真已覆盖，但真实编码器、电压、线缆与噪声 HIL 仍待完成。

### GPIO 可靠性、事件快照、ALARM0、PULSE0 与 FAULT0

GPIO0 的每根输入都会经过两级同步。默认/兼容的 `FILTER_CYCLES=N` 是**整个 12-bit 端口**共享的
N+1 稳定样本窗口；ABI 0.9 的 `FILTER_CTRL.INDEPENDENT_ENABLE=1` 则让 `FILTER_MASK` 选中的每根
pin 分别用 2/4/8 个连续相同样本判定，未选 pin 只有两级同步且不增加等待。独立模式避免无关输入
变化重启正在确认的 pin，但仍不是异步高速采样器或毫秒级机械去抖器。`omcu_gpio_snapshot_arm()` 复用
GPIO 的边沿使能掩码，`omcu_gpio_snapshot_read()` 返回边沿 mask、过滤后输入、run tick、IRQCTRL active
与 reset cause。FAULT0 trip 会优先覆盖该记录并把 `snapshot.forced` 置真，便于故障后诊断。

```c
omcu_gpio_configure_independent_filter(
  OMCU_TN9K_GPIO6,
  OMCU_GPIO_FILTER_CTRL_DEPTH_8
);
omcu_gpio_snapshot_arm(OMCU_TN9K_GPIO6, 0u, false, true);
/* ISR 或主循环： */
omcu_gpio_snapshot_t snapshot;
if (omcu_gpio_snapshot_read(&snapshot) && snapshot.forced) {
  /* 从 FAULT0 获得的优先快照；先使外部系统安全。 */
}
```

ALARM0 使用 `omcu_alarm0_start(prescale)` 时会把 TIMER0 配为无 IRQ 的自由运行 16-bit 时基，随后可用
`omcu_alarm0_schedule_after()` 配置两个独立相对 compare 通道；它们在同一 TIMER0 tick 并行判定，
不存在扫描延迟。若 TIMER0 已由应用配置，则必须先调用 `omcu_alarm0_attach_timer0()`，再只由一个
模块负责 TIMER0 的 prescale/count/compare 配置。PULSE0 使用
`omcu_tn9k_pulse0_configure()`，只能从 GPIO0/J5.8、GPIO1/J5.9、GPIO2/J5.10 中选择一个输入；
切换输入会清空计数和周期 epoch，且不能把它当作高速异步计数器。

FAULT0 使用 GPIO3/J5.11。`omcu_tn9k_fault0_configure()` 会先让 PINMUX 释放该 GPIO 输出，再允许
故障锁存按配置拉低 PWM0/PWM1、释放全部 12 路 GPIO 为高阻并触发强制快照。清锁存必须使用
`omcu_fault0_clear()`，且采样输入已经 inactive；外部急停、隔离、断电或功率级保护仍必须由板级硬件实现。

增强 WDT 由 `omcu_wdt0_start_supervisor()` 配置 pretimeout、最小喂狗窗口和 8 位任务 heartbeat mask。
每个关键任务用 `omcu_wdt0_heartbeat_kick()` 报告进度；任一 required bit 缺失或过早喂狗都会被拒绝并置诊断。
该机制适合发现软件健康状态失真，但不是独立时钟、认证安全 watchdog 或外部故障联锁。

### SYSCTRL：复位诊断与产品 Bootloader 请求

`OMCU_FEATURE_DIAGNOSTICS` 表示当前平台提供可信的顶层复位诊断值。`RESET_CAUSE` 是当前
SoC 这一轮启动的最后原因：外部/上电为 `OMCU_RESET_CAUSE_EXTERNAL`，看门狗为
`OMCU_RESET_CAUSE_WATCHDOG`，软件请求为 `OMCU_RESET_CAUSE_SOFTWARE`。`RUN_TICKS_LO/HI`
是从当前 SoC 释放复位开始的 64-bit 27 MHz 时钟计数，`RESET_COUNT` 是本次外部复位后已发生的
watchdog/software 内部复位数；外部复位会清零该计数和任何未消费的软件请求。

```c
if (omcu_sysctrl_has_diagnostics()) {
  uint32_t cause = omcu_sysctrl_reset_cause();
  uint32_t count = omcu_sysctrl_reset_count();
  uint64_t ticks = omcu_sysctrl_run_ticks();
  (void)cause;
  (void)count;
  (void)ticks;
}
```

`BOOT_CTRL.REQUEST_SUPPORTED=1` 只出现在带 User Flash 的产品 Bootloader 模式。应用不得写
裸魔数，应调用 `omcu_tn9k_request_bootloader()`；它会请求一次 SoC 复位，随后 Boot ROM 确认
pending 并持续保持 UART0 更新会话，直到主机完成常规 `BOOT` 命令或外部复位。该机制不是调试器、
硬件复位替代品或安全边界，也不改变 A/B、CRC、外部复位和空白设备恢复合同。完整流程见
[独立 MCU 固件开发与升级](mcu-firmware-update.md)。

## 把应用加进 SDK

1. 新建 `sdk/examples/<name>/main.c`，只使用 `omcu.h` / `omcu_tn9k.h` 的公开 API。
2. 在 `sdk/CMakeLists.txt` 增加：

   ```cmake
   omcu_add_application(omcu_<name> examples/<name>/main.c)
   ```

3. 在 Windows 执行 `scripts/build-sdk.ps1`，或在 Linux/macOS 执行 `sh scripts/build-sdk.sh`，检查 `.elf`、`.map`、`.bin`、`.omcu`。
4. 使用 `tools/omcu_image.py validate` 核对 `.omcu`，再通过 `tools/omcu_flash.py` 写入已经固化的产品 FPGA。
5. 为新外设事务补充 RTL testbench、串口更新回归和实体板清单，再发布。

`omcu_add_application()` 专门匹配固定的 40 KiB 应用 SRAM 与 User Flash A/B 槽；它不会把客户程序编进 FPGA ROM。若实验性改变 ROM/SRAM 几何，必须创建独立平台与匹配链接脚本，不能混入已交付的产品 MCU 模式。
