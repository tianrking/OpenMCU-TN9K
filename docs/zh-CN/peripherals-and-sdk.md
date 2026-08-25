# 外设、SDK 与应用开发

## 稳定地址空间

| 基址 | 外设 | Tang 顶层连接 |
| ---: | --- | --- |
| `0x2000_0000` | User Flash 窗口 | GW1NR 独立 User Flash；由启动器管理 A/B 应用槽 |
| `0x4000_0000` | GPIO0 | LED0..5、扩展 GPIO0..2 |
| `0x4000_1000` | UART0 | package pad 17/18 |
| `0x4000_2000` | TIMER0 | 片内计数器 |
| `0x4000_3000` | SPI0 | CS/MOSI/SCK/MISO |
| `0x4000_4000` | I2C0 | 开漏 SCL/SDA |
| `0x4000_5000` | WDT0 | 连接 Tang 顶层复位序列器 |
| `0x4000_6000` | PWM0 | 一路 PWM pad |
| `0x4000_7000` | IRQCTRL | 六个外设来源的 sticky、屏蔽、强制与优先级视图 |
| `0x4000_F000` | SYSCTRL | `OMCU` ID、ABI、功能位、内存容量 |

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
omcu_gpio_enable_output(OMCU_TN9K_LED0 | OMCU_TN9K_GPIO0);
omcu_gpio_set(OMCU_TN9K_LED0);       /* LED0 点亮：顶层处理低有效极性 */
omcu_gpio_toggle(OMCU_TN9K_GPIO0);  /* 扩展 GPIO0 切换 */
omcu_gpio_disable_output(OMCU_TN9K_GPIO0); /* 释放为高阻输入 */
```

### 中断与 IRQCTRL

IRQCTRL 已把 GPIO0/UART0/TIMER0/SPI0/I2C0/WDT0 分别映射为 CPU bit 8..13；应用程序
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

### SPI0

SPI0 是 8-bit、MSB-first、mode 0 主机。默认每次 `START` 自动拉低一个 CS 并传输一个
字节；ABI `0.6` 增加 `CTRL.CS_HOLD`，使多个字节 `START` 可以共用同一次低有效 CS：

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

### PWM0 与 WDT0

```c
omcu_pwm0_configure(26u, 999u, 500u, false); /* 约 1 kHz，50% */
omcu_wdt0_start(27000000u, true, false);     /* 约 1 s；应用循环需喂狗 */
omcu_wdt0_feed();
```

PWM 为单通道边沿对齐输出，`PERIOD` 为包含端点的 top 值。看门狗超时的复位请求已经
在 Tang 顶层仿真中验证会重启 SoC；实际板上复位行为仍需记录。

## 把应用加进 SDK

1. 新建 `sdk/examples/<name>/main.c`，只使用 `omcu.h` / `omcu_tn9k.h` 的公开 API。
2. 在 `sdk/CMakeLists.txt` 增加：

   ```cmake
   omcu_add_application(omcu_<name> examples/<name>/main.c)
   ```

3. 在 Windows 执行 `scripts/build-sdk.ps1`，或在 Linux/macOS 执行 `sh scripts/build-sdk.sh`，检查 `.elf`、`.map`、`.bin`、`.omcu`。
4. 使用 `tools/omcu_image.py validate` 核对 `.omcu`，再通过 `tools/omcu_flash.py` 写入已经固化的产品 FPGA。
5. 为新外设事务补充 RTL testbench、串口更新回归和实体板清单，再发布。

`omcu_add_application()` 专门匹配固定的 40 KiB 应用 SRAM 与 User Flash A/B 槽；它不是把程序编进 FPGA ROM。`omcu_add_firmware()` 仅保留给旧式 bring-up 回归。若实验性改变 ROM/SRAM 几何，必须使用独立目标和匹配的链接脚本，不能混入产品 MCU 模式。
