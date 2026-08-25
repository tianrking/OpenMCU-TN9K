# Tang Nano 9K 平台封装

此目录提供 `GW1NR-LV9QN88PC6/I5`（`GW1N-9C`）的 OpenMCU FPGA 后端。它处理 27 MHz 时钟、复位同步、Gowin RAM/Flash 原语和经过约束文件审查的外部管脚；通用 SoC 和寄存器 ABI 不应泄漏 Gowin 原语。

## 两个顶层，必须选对

| 顶层 | 用途 | ROM 内容 | 客户应用路径 |
| --- | --- | --- | --- |
| `omcu_tn9k_bringup_top` | 旧式 RTL / 外设 / P&R bring-up | 可替换 `.hex` 测试程序 | 不提供产品升级承诺 |
| `omcu_tn9k_mcu_top` | 推荐的产品 MCU 模式 | 固定 `omcu_bootloader.hex` | `.omcu → UART0 → User Flash A/B` |

`omcu_tn9k_mcu_top` 使用 GW1NR 的 608 Kbit User Flash（76 KiB）控制器。它与 FPGA 配置 Flash 是不同的存储域：前者储存客户应用，后者只储存稳定的 FPGA 平台配置。

## 外设到实际管脚的映射

| 逻辑资源 | Tang Nano 9K 管脚 / 说明 |
| --- | --- |
| GPIO0[0:5] | 六个板载低有效 LED |
| UART0 | 封装管脚 17 / 18 |
| SPI0 | 38 / 37 / 36 / 39，与 J5 / TF 信号组共享 |
| I2C0 | 26 / 27，真正开漏结构，需要正确的外部上拉 |
| PWM0 | 25 |
| GPIO0[6:17] | 12 路三态扩展管脚 28 / 29 / 30 / 33 / 34 / 40 / 35 / 41 / 42 / 51 / 53 / 54；GPIO3..11 与 RGB LCD 共线 |
| UART1（PINMUX） | GPIO10/11 → J5.18/J5.19（pad 53/54），UART0 仍保留给启动器和升级 |
| PWM1（PINMUX） | GPIO4..7 → J5.12..15（pad 34/40/35/41），四路共享计数器 |
| TIMER1（PINMUX） | GPIO8/9 → J5.16/J5.17（pad 42/51），输入专用的同步滤波 capture / 正交 A/B |

物理电平、连接器编号、SPI/TF 冲突和 I2C 上拉不是 RTL 仿真可证明的事项，接线前请先阅读 [硬件与引脚](../../../docs/zh-CN/hardware-and-pins.md)。

## 构建产品 MCU 位流

先构建 SDK，以获得启动器 ROM；再调用 `-McuMode`。该模式固定为 8 KiB ROM + 44 KiB SRAM，拒绝任意更改该产品内存几何，避免 SDK 链接脚本与硬件不一致。

```powershell
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
$tools = 'C:\toolchains\yowasp-gowin\Scripts'
.\scripts\build-tangnano9k-open.ps1 -McuMode `
  -ToolBin $tools `
  -BuildDirectory .\build\tangnano9k-mcu
```

输出目录包含：

- `omcu_tn9k_mcu.fs`：待下载 FPGA 位流；
- `omcu_tn9k_mcu_manifest.json`：设备、顶层、模式、位流哈希、ROM 初始化、User Flash 布局和资源报告；
- `omcu_rom_image.hex`：为 `$readmemh` 生成的稠密启动器 ROM；
- Yosys / nextpnr 日志和 JSON 报告。

开放流程会检查设备、全部规范 RTL 源、CST/SDC 和 27 MHz 时序；它生成的 P&R 结果仍不等于实体板通过。

## 下载策略

始终使用受 manifest 与 SHA-256 保护的下载脚本。它默认写入易失 SRAM：

```powershell
.\scripts\program-tangnano9k.ps1 `
  -BitstreamPath .\build\tangnano9k-mcu\omcu_tn9k_mcu.fs `
  -Destination sram
```

只有复位、串口、LED、外设和异常恢复检查完成后，才使用：

```powershell
.\scripts\program-tangnano9k.ps1 `
  -BitstreamPath .\build\tangnano9k-mcu\omcu_tn9k_mcu.fs `
  -Destination flash -ConfirmFlash
```

`flash` 在此命令中指 FPGA 配置 Flash。产品交付后，客户不要再运行此命令更新业务程序；请改用 [`tools/omcu_flash.py`](../../../tools/omcu_flash.py) 更新 User Flash 应用槽。

## 验证边界

顶层仿真和 P&R 可以检查数字连接、复位释放、约束和资源；它们不能验证 USB 下载器、供电、Bank 电压、板载 LED 极性、真实串口电平、User Flash 擦写、TF 卡冲突或外围设备响应。板级测试必须单独记录，见 [测试计划](../../../tests/README.md)。
