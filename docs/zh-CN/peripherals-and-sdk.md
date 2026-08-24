# 外设、SDK 与应用开发

## 稳定地址空间

| 基址 | 外设 | Tang 顶层连接 |
| ---: | --- | --- |
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
                          OMCU_FEATURE_WDT0 | OMCU_FEATURE_PWM0;

if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
    !omcu_hw_has_feature(required)) {
  for (;;) { }
}
```

不要仅凭 bitstream 文件名判断硬件版本。`SYSCTRL` 会报告 ABI 主版本、功能位和实际
ROM/SRAM KiB；如果 ABI 主版本不同，应用应拒绝运行。

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

SPI0 是 8-bit、MSB-first、mode 0 主机，每次 `START` 自动拉低一个 CS 并传输一个字节：

```c
uint8_t rx;
omcu_spi0_init(13u, false);  /* 约 1 MHz：27 MHz / (2 * (13 + 1)) */
if (!omcu_spi0_transfer(0x9fu, &rx)) {
  /* 处理未使能或异常状态 */
}
```

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
2. 在 `sdk/CMakeLists.txt` 增加 `omcu_add_firmware(omcu_<name> examples/<name>/main.c)`。
3. 在 Windows 执行 `scripts/build-sdk.ps1`，或在 Linux/macOS 执行
   `sh scripts/build-sdk.sh`，检查 `.elf`、`.map`、`.hex`。
4. 将 `.hex` 作为 `build-tangnano9k-open.ps1 -RomInitFile` 输入，不要手改 RTL ROM。
5. 为新外设事务补充 RTL testbench 和实体板清单，再发布。

SDK 的当前链接脚本专门对应 Tang 满配 8 KiB ROM / 44 KiB SRAM。若为更小的实验配置
编译，必须创建匹配的 target linker script，而不是让链接器静默生成越界镜像。
