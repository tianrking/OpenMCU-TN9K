# 构建、产物校验与安全烧录

## 1. 准备可重复的工具链

RISC-V SDK 使用 GNU bare-metal 工具链；推荐 `riscv-none-elf-` 前缀。开放 FPGA 流
的锁定版本在 [`toolchains/yowasp-gowin.lock.json`](../../toolchains/yowasp-gowin.lock.json)。
Windows 上建议使用 64-bit Python 3.10 或更高版本安装锁定的 YoWASP/Apycula 包；旧的
Python 3.9 可能没有 `fastcrc` 的预编译 wheel，进而错误地要求本机 Rust 编译环境。

```powershell
git submodule update --init --recursive

# 示例：使 GNU 工具链对脚本可见。
$env:PATH = 'C:\toolchains\xpack-riscv-none-elf\bin;' + $env:PATH

# 若 cmake/ninja 不在 PATH，可明确给出路径。
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
```

Linux/macOS 的 SDK 构建不依赖 PowerShell；使用同一个 CMake toolchain file、同一个
链接脚本与相同的 GNU 前缀约定：

```sh
git submodule update --init --recursive
export PATH="/opt/xpack-riscv-none-elf/bin:$PATH"
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
```

两份入口脚本均会先检查 `gcc` 和 `objcopy`，再配置 CMake。推荐的 xPack 包为
`@xpack-dev-tools/riscv-none-elf-gcc@15.2.0-1.1`；它可通过 `xpm` 在各宿主系统安装。
Windows、Linux、macOS CI 都会编译全部 SDK 固件，Linux 还执行 RTL 仿真；这些自动化
结果不取代真实板卡测试。

生成的 `.elf`、`.map`、`.hex` 均位于 `build/sdk/`。`.hex` 是每 32-bit word 的 Verilog
ROM 初始化文件，而非能够直接被 openFPGALoader 下载的 FPGA 配置文件。

可用示例：

| 目标 | 目的 |
| --- | --- |
| `omcu_blink` | 逻辑 LED 闪烁。 |
| `omcu_uart_hello` | UART0 启动文本。 |
| `omcu_isa_smoke` | 编译器产生的 RV32IMC 指令端到端测试。 |
| `omcu_peripheral_smoke` | SPI、PWM、看门狗和 GPIO 的仿真集成测试。 |
| `omcu_i2c_smoke` | I2C 字节事务与目标夹具测试。 |
| `omcu_irq_smoke` | TIMER0 -> IRQCTRL -> 固定向量 -> C handler -> `RETIRQ` 端到端测试。 |
| `omcu_wdt_reset_smoke` | 看门狗触发 Tang 顶层复位。 |
| `omcu_tn9k_board_demo` | 面向实体板的 UART/PWM/三路扩展 GPIO/看门狗演示。 |

## 2. 生成 Tang Nano 9K `.fs`

```powershell
$tools = 'C:\toolchains\yowasp-gowin\Scripts'
.\scripts\build-tangnano9k-open.ps1 -ToolBin $tools `
  -BuildDirectory .\build\tangnano9k-board-demo `
  -RomInitFile .\build\sdk\omcu_tn9k_board_demo.hex
```

默认的 Tang 顶层参数为 `-RomKiB 8 -SramKiB 44`，对应 8 KiB ROM 和 44 KiB SRAM。
在改变任意一个参数前，先证明应用链接脚本、ROM 镜像和 P&R 报告仍相互匹配；不要在
固件仍使用 8 KiB/44 KiB 链接脚本时随意缩小 FPGA 存储。

构建脚本必须成功完成 Yosys、nextpnr 和 `gowin_pack`，并生成：

- `omcu_tn9k_bringup.fs`：要下载的 FPGA 配置；
- `omcu_rom_image.hex`：由 SDK 稀疏 `.hex` 展开得到的完整 ROM 映像；未写入的 word
  会填入 RISC-V NOP，避免出现可执行的未初始化空洞；
- `omcu_tn9k_bringup_manifest.json`：精确工具版本、原始 ROM 与有效 ROM 的 SHA-256、
  综合前后 Boot ROM BSRAM 初始化指纹、内存参数、时序、资源和 `.fs` SHA-256；
- P&R report/JSON 与 `yosys.log` / `nextpnr.log`：发布审计证据。

这里的 ROM 处理不是把文件名记录在 manifest 就结束：脚本在 Yosys 读取包含
`$readmemh` 的 Boot ROM 模块前生成配置，并对综合网表与 P&R 网表中四个 Boot ROM
BSRAM 的 `INIT_RAM_xx` 内容分别计算 SHA-256 指纹。两者不一致时构建直接失败。因此，
manifest 中的 `rom_embedding.verified=true` 表示本次 SDK 映像确实保持到 P&R 网表，
但仍不表示已经通过实体板测试。

脚本检测锁定的 GW1NR-LV9QN88PC6/I5 目标、RTL 清单和约束覆盖；时钟低于 27 MHz
约束会直接失败。构建成功仍不等于实体板可用。

## 3. 先做安全的 SRAM 下载

安装支持 `tangnano9k` board 名称的 openFPGALoader，并让其位于 `PATH`。默认命令
只写易失 SRAM：

```powershell
$fs = '.\build\tangnano9k-board-demo\omcu_tn9k_bringup.fs'

# 只显示将执行的操作，不触碰硬件。
.\scripts\program-tangnano9k.ps1 -BitstreamPath $fs -WhatIf

# 真正下载到 SRAM；复位或断电后配置消失。
.\scripts\program-tangnano9k.ps1 -BitstreamPath $fs -Destination sram
```

脚本计算 `.fs` SHA-256，默认要求同目录 manifest 中的哈希、器件和系列完全匹配。此
保护避免把旧 bitstream 或错误器件的文件误下载到板卡。

## 4. Flash 是显式破坏性操作

Flash 下载会改写 FPGA 的持久启动配置。只能在 SRAM 运行、板级检查、哈希审核都通过后
执行，并且必须同时给出双重确认：

```powershell
.\scripts\program-tangnano9k.ps1 -BitstreamPath $fs `
  -Destination flash -ConfirmFlash
```

保持 USB 电源稳定，不在下载中拔线。下载命令成功只表示主机工具返回成功；随后仍应断电
重启并重跑 UART/GPIO/PWM/SPI/I2C 检查。脚本不会也不能替代逻辑分析仪、示波器或人工
板级观察。

## 5. 发布前的最小复核

```powershell
.\scripts\generate-sdk.ps1 -Check
.\scripts\check-tangnano9k-project.ps1

$env:OMCU_IVERILOG_BIN = 'C:\toolchains\iverilog\bin'
.\scripts\run-rtl-smoke.ps1 -Test tn9k
.\scripts\run-rtl-smoke.ps1 -Test tn9k-peripherals
.\scripts\run-rtl-smoke.ps1 -Test irqctrl
.\scripts\run-rtl-smoke.ps1 -Test sdk-irq
```

再保存 manifest、SDK `.hex` 哈希、Git commit、串口日志和板级测量记录。发布者必须能
复现的是“某一个 commit + 某一个 ROM + 某一个工具版本”的确切 MCU 镜像。
