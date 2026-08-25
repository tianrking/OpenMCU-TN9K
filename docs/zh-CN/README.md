# OpenMCU-TN9K 中文开发总览

OpenMCU-TN9K 的目标不是“把一次演示程序塞进 FPGA”的临时工程，而是把 Tang Nano 9K 做成一个可交付的 FPGA MCU 平台：硬件平台只在发布时固化一次，客户软件之后以独立 MCU 固件的方式持续开发和升级。

![OpenMCU 产品固件分层](assets/openmcu-product-flow.svg)

## 先判断你处在哪条开发线

| 你是谁 | 主要工作 | 需要接触的文件 | 不应该做的事 |
| --- | --- | --- | --- |
| FPGA / 硬件工程师 | 修改 RTL、构建 `-McuMode` 位流、完成生产固化 | `rtl/`、`scripts/build-tangnano9k-open.ps1` | 为每个客户 C 程序重新生成 `.fs` |
| 客户应用开发者 | 编写裸机 C/C++、生成 `.omcu`、通过 UART 更新 | `sdk/`、`tools/omcu_flash.py` | 修改 Verilog、重烧配置 Flash |
| 测试 / 发布工程师 | 运行仿真、交叉编译、P&R、实板和异常断电矩阵 | `tests/`、`scripts/`、本文档 | 把 CI 或一次下载命令当成实板/量产证据 |

```mermaid
flowchart LR
  A[平台工程：Bootloader .hex] --> B[MCU 产品位流 .fs]
  B --> C[配置 Flash：一次固化]
  D[客户工程：C/C++] --> E[独立 .omcu]
  E --> F[UART0 更新]
  F --> G[User Flash A/B]
  C --> H[复位后的启动器]
  G --> H
  H --> I[复制到 SRAM 并执行]
```

## 推荐阅读顺序

1. [独立 MCU 固件开发与升级](mcu-firmware-update.md)：产品流程、A/B 槽、UART 协议、恢复和安全边界。
2. [硬件与引脚](hardware-and-pins.md)：Tang Nano 9K 的电压、引脚、串口、I2C 和 SPI 注意事项。
3. [构建与烧录](build-and-program.md)：可重复 SDK / FPGA 构建，SRAM 试运行和配置 Flash 固化。
4. [外设与 SDK](peripherals-and-sdk.md)：C API、寄存器和示例边界。
5. [中断开发约定](interrupts.md)：PicoRV32 自定义 IRQ ABI、固定向量和 ISR 规则。
6. [验证与发布状态](validation-and-release.md)：证据层级与对外发布门槛。

## 平台首次构建：FPGA 工程

从仓库根目录开始。初始化独立许可覆盖的 PicoRV32 子模块，再准备 CMake、Ninja、GNU RISC-V 工具链和锁定版本的 Gowin 开放构建工具。

```powershell
git submodule update --init --recursive
$env:PATH = 'C:\toolchains\riscv-none-elf\bin;' + $env:PATH

# 同时生成 Boot ROM 启动器和 .omcu 示例应用。
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-

$tools = 'C:\toolchains\yowasp-gowin\Scripts'
.\scripts\build-tangnano9k-open.ps1 -McuMode `
  -ToolBin $tools `
  -BuildDirectory .\build\tangnano9k-mcu
```

`-McuMode` 固定产品内存结构：8 KiB Boot ROM、44 KiB SRAM（40 KiB 应用区加 4 KiB 启动器工作区）和 76 KiB User Flash。该模式只把 `omcu_bootloader.hex` 放进 FPGA ROM；它不会把 `omcu_mcu_blink.omcu` 或客户应用混进位流。

先用 SRAM 下载验证，再审阅 `omcu_tn9k_mcu_manifest.json`、位流哈希和板级功能，最后才用 `-Destination flash -ConfirmFlash` 写入持久 FPGA 配置。详细命令见 [构建与烧录](build-and-program.md)。

## 客户应用日常开发：MCU 工程

```powershell
# 在 sdk/CMakeLists.txt 使用 omcu_add_application() 声明自己的目标后：
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
python -m pip install pyserial
python .\tools\omcu_flash.py --port COM5 --image .\build\sdk\my_product_app.omcu
```

启动器在复位后短暂监听 UART；先运行 PC 工具、再按复位键即可进入更新。更新器使用带序号和 CRC32 的停等协议，始终写入非当前槽，全部验证后才原子提交新槽。它是客户使用的“烧录 MCU 程序”通道。

## 当前 ABI 与边界

- ISA / ABI：`rv32imc` / `ilp32`，PicoRV32 适配器；当前硬件 ABI `0x00000005`。
- 外设：GPIO0、UART0、TIMER0、SPI0、I2C0、WDT0、PWM0、IRQCTRL、SYSCTRL、User Flash 控制器。
- 更新完整性：镜像头和载荷均使用 CRC32，支持断电前的旧槽回退；它不是签名安全启动。
- 真实硬件：RTL、SDK 和 P&R 检查的证据与实体板电气、擦写寿命、掉电和量产验证是不同层级，不能相互替代。
- 旧 `.hex → .fs` 路径：仅为 RTL / FPGA bring-up 回归保留；客户交付一律使用 `.omcu → UART → User Flash`。

英文文档会在中文内容与流程稳定后统一翻译；当前仓库自有 README 以中文为准。
