# OpenMCU-TN9K 中文开发总览

OpenMCU-TN9K 把 Tang Nano 9K 实现为一个可由裸机 C 程序使用的
**RV32IMC FPGA MCU**：CPU、ROM/SRAM、GPIO、UART、定时器、SPI、I2C、看门狗、
PWM、IRQCTRL 和 SYSCTRL 都在同一个 FPGA 配置中。第三方使用者的入口不是修改 Verilog，
而是“编译 SDK 程序 -> 生成 `.hex` -> 构建 `.fs` -> 安全下载 -> 执行板级检查”。

开放构建不会只把 `.hex` 路径写到 manifest：它会生成完整的 NOP 填充 ROM 映像，在
`$readmemh` 解析期把该映像写入 Boot ROM，并比较综合网表与 P&R 网表的 BSRAM 初始化
指纹。这样第三方能区分“请求了某个固件”与“该固件确实进入最终 `.fs`”。

这套资料刻意把“已经验证”和“需要真实硬件验证”分开。当前仓库有 RTL 仿真、SDK
编译和开放 P&R 证据；当前工作区没有检测到已连接的 Tang Nano 9K，因此没有声称
任何 `.fs` 已在实体板上运行。请先阅读
[验证与发布状态](validation-and-release.md) 后再把它用于外部产品。

## 先读这五份资料

1. [硬件与引脚](hardware-and-pins.md)：板上资源、I/O、电平、连线和冲突。
2. [构建与烧录](build-and-program.md)：可重复 SDK / `.fs` 构建与默认安全的 SRAM 下载。
3. [外设与 SDK](peripherals-and-sdk.md)：寄存器、C API、例程和应用边界。
4. [中断开发约定](interrupts.md)：IRQCTRL、固定向量、C ISR 与清除顺序。
5. [ARM 版本授权与集成](arm-license-and-integration.md)：为什么没有把未授权的
   Cortex-M RTL 冒充成可发布 ARM MCU，以及获得授权后如何接入。

## 五分钟构建路径

从仓库根目录执行。先初始化被独立许可覆盖的 PicoRV32 子模块：

```powershell
git submodule update --init --recursive

# 将你的 GNU RISC-V 工具链 bin 目录加入 PATH；xPack 通常使用此命名前缀。
$env:PATH = 'C:\toolchains\riscv-none-elf\bin;' + $env:PATH
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
```

Linux 和 macOS 使用同一份 CMake 配置与链接脚本，只是入口脚本采用 POSIX shell：

```sh
git submodule update --init --recursive
export PATH="/opt/xpack-riscv-none-elf/bin:$PATH"
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
```

Windows、Linux、macOS 的 CI 都会编译全部 SDK 示例；Linux 还运行完整 RTL/固件仿真。
跨平台“构建通过”不等于实体板电气测试通过。

然后用锁定版本的开放 Gowin 流将一个 SDK 程序合进 FPGA ROM：

```powershell
$tools = 'C:\toolchains\yowasp-gowin\Scripts'
.\scripts\build-tangnano9k-open.ps1 -ToolBin $tools `
  -BuildDirectory .\build\tangnano9k-board-demo `
  -RomInitFile .\build\sdk\omcu_tn9k_board_demo.hex
```

成功时，目录中会有 `.fs`、P&R JSON、日志和包含 SHA-256 的 manifest。先使用默认的
易失 SRAM 下载确认连线；它断电即失效，不会改写板上的持久配置：

```powershell
.\scripts\program-tangnano9k.ps1 `
  -BitstreamPath .\build\tangnano9k-board-demo\omcu_tn9k_bringup.fs `
  -Destination sram
```

只有完成板级检查、复核 manifest 哈希且接受覆盖持久配置后，才使用
`-Destination flash -ConfirmFlash`。脚本会拒绝没有同目录 manifest 或哈希不匹配的
产物；不要用 `-AllowUnverifiedArtifact` 绕过正常发布流程。

## 这不是“用完每一个逻辑单元”的噱头

默认 Tang 配置选择 8 KiB ROM + 44 KiB SRAM，目标是让可用的 BSRAM 用于真正的软件
容量，而不是人为填充无用逻辑。LUT、ALU 或 DSP 未使用的部分应留给将来的实际功能
（例如 DMA、片外 RAM 控制器、更多 PWM 通道或协议外设）；仅为了提高利用率而填充
空逻辑会降低时序余量和可维护性。构建 manifest 和验证文档记录每一版真实资源报告，
而不是用固定数字宣传。

## 当前 RISC-V 架构范围

- ISA：PicoRV32 适配器，编译目标 `rv32imc` / `ilp32`；M、C 指令已由编译产物端到端
  仿真覆盖。
- 片上存储：Tang Nano 9K 默认 8 KiB 初始化 ROM + 44 KiB SRAM；容量可由顶层参数
  调整，但调整时必须同步使用匹配的链接脚本。
- 外设：GPIO0、UART0、TIMER0、SPI0、I2C0、WDT0、PWM0、IRQCTRL、SYSCTRL。
- 时钟：直接使用板上 27 MHz；没有对 PLL、PSRAM、QSPI-XIP、DMA、JTAG/调试器或
  USB 协议栈作出已完成的承诺。
- 中断：IRQCTRL 将六个外设来源固定映射到 CPU bit 8..13；SDK 已有 `0x10` 向量、
  完整整数寄存器保存、C `omcu_irq_dispatch()` 回调与 `RETIRQ` 返回。它是 PicoRV32
  自定义 ABI，不是标准机器模式 / CSR / PLIC；详见 [中断开发约定](interrupts.md)。

完整寄存器 ABI 在英文的 [registers.md](../registers.md)，稳定架构约束在
[architecture.md](../architecture.md)。
