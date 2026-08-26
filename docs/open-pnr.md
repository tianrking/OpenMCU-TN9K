# Tang Nano 9K 开源综合、布局布线与打包

`scripts/build-tangnano9k-open.ps1` 用开源实现链从 OpenMCU RTL 生成 Tang Nano 9K 的 FPGA
配置镜像：

```text
SystemVerilog → Yosys synth_gowin → nextpnr-himbaechel-gowin → gowin_pack → .fs
```

目标固定为 `GW1NR-LV9QN88PC6/I5` / `GW1N-9C`。脚本会检查产品工程是否覆盖
`rtl/files.f` 的全部规范 RTL、恰好一份 CST/SDC、固定产品内存几何以及 27 MHz 时钟约束；
它不会依赖 IDE 悄悄漏掉新增外设。

## 产品模式

> `-McuMode` 是客户交付默认路径：位流只含稳定硬件、Boot ROM 启动器和 User Flash 控制器；
> 客户应用永远是 UART0 写入的独立 `.omcu`，不通过 `RomInitFile` 混入 `.fs`。

```powershell
git submodule update --init --recursive

$tools = 'C:\toolchains\yowasp-gowin\Scripts'
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
.\scripts\build-tangnano9k-open.ps1 -McuMode `
  -ToolBin $tools `
  -BuildDirectory .\build\tangnano9k-mcu
```

输出目录含：

- `omcu_tn9k_mcu.fs`：待下载的 FPGA 配置镜像；
- `omcu_tn9k_mcu_manifest.json`：器件、顶层、工具、ROM 哈希链、User Flash 几何、时序、资源和 `.fs` SHA-256；
- `omcu_tn9k_mcu_report.json`：时钟/资源报告；
- `omcu_tn9k_mcu.json` 与 `omcu_tn9k_mcu_pnr.json`：综合/P&R 网表；
- `omcu_rom_image.hex`：由 Boot ROM 源生成的稠密 ROM 镜像。

## ROM 初始化可追溯性

产品 Boot ROM 输入先被转换为固定 1,024 word、RISC-V NOP 填充的镜像，并作为 `$readmemh`
的实际输入。构建会对两个 Boot ROM BSRAM 单元的初始化数据在综合网表和 P&R 网表中计算指纹；
若两者不一致则失败。因此 manifest 能证明本次启动器确实进入了最终网表，而不是仅记录一个期望的
输入文件名。

`-RomKiB` / `-SramKiB` 仅用于受控实验。产品模式固定 4 KiB Boot ROM + 44 KiB SRAM；改变
几何必须同时更换 SDK 链接脚本，不能冒充标准 MCU 位流。

## 当前结果与证据边界

ABI 0.9 的 P&R 指纹、资源和时序必须记录在同一源码构建产生的
[验证与发布状态](zh-CN/validation-and-release.md) 和 `omcu_tn9k_mcu_manifest.json` 中。不要用 ABI 0.6 或 ABI 0.7
历史 manifest 替代本版证据。生成目录是构建产物，不纳入 Git；发布时应把该 manifest、报告、日志和位流
SHA-256 作为可追溯工件保存。

当前可复核产品构建为 `build/tangnano9k-mcu-abi09-independent-history-filter-packed/`：4 KiB ROM、44 KiB SRAM、
27 MHz 约束下 44.295 MHz 实现频率和 14.461 ns 裕量；资源为 LUT4 `7184/8640`、DFF `2610/6480`、
BSRAM `24/26`。这组数字仅对应同一源码的开源 P&R/packing，不是实体板时钟、电气或 Flash HIL 结果。

Yosys 目前会对顶层 I2C/GPIO 三态 Pad 报告已知的有限支持警告；P&R/packing 成功不应被描述成
“零警告签核”。更重要的是：开源 P&R 不能证明实体板下载、USB/供电、复位、Bank 电压、UART
电平、User Flash 擦写、TF 互斥或外设响应。

## 下载策略

先下载到易失 SRAM：

```powershell
.\scripts\program-tangnano9k.ps1 `
  -BitstreamPath .\build\tangnano9k-mcu\omcu_tn9k_mcu.fs `
  -Destination sram
```

脚本会核对相邻 manifest 的位流 SHA-256。只有完成实体板 HIL 后，才可以执行配置 Flash 固化：

```powershell
.\scripts\program-tangnano9k.ps1 `
  -BitstreamPath .\build\tangnano9k-mcu\omcu_tn9k_mcu.fs `
  -Destination flash -ConfirmFlash
```

这里的 `flash` 是 FPGA 配置存储。产品交付后，日常业务程序只能用
`tools/omcu_flash.py --port COMx --image my_app.omcu` 更新 User Flash A/B 槽；不要为每次客户
应用重新 P&R 或改写配置 Flash。

## 历史 bring-up 路径

不带 `-McuMode` 的路径仍可把 `.hex` 作为 ROM 初始化用于 RTL、编译器和 P&R 回归。它不是客户
更新接口，也不替代 ABI 0.9 产品模式的 P&R 与 HIL 证据。
