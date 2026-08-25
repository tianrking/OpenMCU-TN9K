# 构建、平台固化与应用烧录

本文将两种“烧录”严格分开：

1. **FPGA 平台固化**：硬件方把带启动器的 `omcu_tn9k_mcu.fs` 写入 Tang 的配置 Flash；
2. **MCU 应用烧录**：客户把独立 `*.omcu` 通过 UART0 写入 FPGA 的 User Flash A/B 槽。

第二种才是客户日常开发流程。不要把客户 `.hex` 编进 FPGA 位流，也不要用 FPGA 下载器替代应用升级器。

## 1. 准备可重复的工具链

SDK 使用 GNU bare-metal RISC-V 工具链，推荐 `riscv-none-elf-` 前缀。开放 FPGA 流的锁定版本记录在 [`toolchains/yowasp-gowin.lock.json`](../../toolchains/yowasp-gowin.lock.json)。Windows 建议使用 64 位 Python 3.10 或更新版本安装 YoWASP/Apycula。

```powershell
git submodule update --init --recursive

# 示例：按实际安装目录修改。
$env:PATH = 'C:\toolchains\riscv-none-elf\bin;' + $env:PATH

# 建议将 FPGA 工具放在隔离虚拟环境中。
python -m venv .venv\yowasp-gowin
.\.venv\yowasp-gowin\Scripts\python -m pip install `
  yowasp-yosys==0.68.0.0.post1208 `
  yowasp-nextpnr-himbaechel-gowin==0.11.1.0.post826 `
  apycula==0.32
```

Linux/macOS 使用相同 CMake 工程与链接脚本：

```sh
git submodule update --init --recursive
export PATH="/opt/xpack-riscv-none-elf/bin:$PATH"
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
```

自动化构建和仿真是可重复性证据，不是实体板、电气、掉电或量产资格证据。

## 2. 构建一次性 FPGA MCU 平台

SDK 构建同时产生不可变启动器和独立应用示例：

```powershell
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
```

主要产物：

| 文件 | 用途 |
| --- | --- |
| `build\sdk\omcu_bootloader.hex` | 进入产品 FPGA 的 8 KiB Boot ROM；不是客户更新包。 |
| `build\sdk\omcu_mcu_blink.omcu` | 独立应用示例；可经 UART 更新。 |
| 其他 `*.hex` | 旧 ROM/RTL bring-up 回归输入；不属于客户交付路径。 |

构建产品位流时必须使用 `-McuMode`：

```powershell
$tools = (Resolve-Path .\.venv\yowasp-gowin\Scripts).Path
.\scripts\build-tangnano9k-open.ps1 -McuMode `
  -ToolBin $tools `
  -BuildDirectory .\build\tangnano9k-mcu
```

该模式固定 8 KiB Boot ROM + 44 KiB SRAM（40 KiB 应用区加 4 KiB 启动器工作区），启用 76 KiB GW1NR User Flash。脚本会生成并核验：

- `omcu_tn9k_mcu.fs`：产品 FPGA 配置；
- `omcu_tn9k_mcu_manifest.json`：器件、顶层、`mcu_mode`、工具版本、ROM 嵌入、User Flash 几何、时序、资源和位流 SHA-256；
- `omcu_rom_image.hex`：填充后的 Boot ROM 初始化内容；
- Yosys / nextpnr 日志、JSON 和报告。

ROM 嵌入检查会比较综合网表与 P&R 网表的 Boot ROM 初始化指纹。这个检查证明本次启动器输入保留到了网表，不证明实体板已通过。

## 3. 安全固化 FPGA 配置

先写入易失 SRAM，验证板卡和产物，再写入持久配置 Flash：

```powershell
$fs = '.\build\tangnano9k-mcu\omcu_tn9k_mcu.fs'

# 只显示操作，不接触硬件。
.\scripts\program-tangnano9k.ps1 -BitstreamPath $fs -WhatIf

# 易失验证；断电或复位后配置消失。
.\scripts\program-tangnano9k.ps1 -BitstreamPath $fs -Destination sram

# 仅在 SRAM 验证、manifest 审核和板级检查完成后执行。
.\scripts\program-tangnano9k.ps1 -BitstreamPath $fs `
  -Destination flash -ConfirmFlash
```

下载脚本默认要求位流旁的 `omcu_tn9k_mcu_manifest.json`、目标器件和 SHA-256 都匹配。`-Destination flash` 改写的是 **FPGA 配置 Flash**，不是客户应用槽；稳定供电、不要中断下载。

## 4. 客户构建并烧录 MCU 应用

客户应用必须通过 `omcu_add_application()` 生成 `.omcu`，详细写法见 [SDK README](../../sdk/README.md)。构建后的日常升级不再调用 FPGA 构建工具：

```powershell
python -m pip install pyserial
python .\tools\omcu_image.py validate `
  --image .\build\sdk\my_product_app.omcu
python .\tools\omcu_flash.py `
  --port COM5 `
  --image .\build\sdk\my_product_app.omcu
```

使用 3.3 V TTL UART、`115200 / 8N1`、TX/RX 交叉和共地。先启动 PC 工具，再在默认连接窗口内按一次复位键。启动器会对帧、硬件 ABI、镜像头和载荷进行 CRC 校验，写入非当前 User Flash 槽，校验成功后才原子提交；掉电或传输中断发生在提交前时，旧的有效槽仍能启动。

完整 A/B 槽、协议、恢复和安全限制见 [独立 MCU 固件开发与升级](mcu-firmware-update.md)。

## 5. 发布前的最小复核

```powershell
.\scripts\generate-sdk.ps1 -Check
.\scripts\check-tangnano9k-project.ps1 -McuMode

$env:OMCU_IVERILOG_BIN = 'C:\toolchains\iverilog\bin'
.\scripts\run-rtl-smoke.ps1 -Test user-flash
.\scripts\run-rtl-smoke.ps1 -Test mcu-top
python -m unittest tools.tests.test_omcu_image tools.tests.test_omcu_flash_protocol -v
```

随后保存 Git commit、SDK 构建记录、`omcu_tn9k_mcu_manifest.json`、`.omcu` 哈希、下载器版本、串口日志和实板记录。实板必须覆盖首次固化、冷启动、空白恢复、正常升级、丢包/重复包、错误 CRC/ABI、多个断电时点和外设电气检查。

## 旧式 bring-up 流程（仅回归用途）

`omcu_add_firmware()` 生成的 `.hex` 与 `omcu_tn9k_bringup_top` 仍用于已有 RTL、编译器和 FPGA P&R 回归。只有在维护这些测试时才提供 `-RomInitFile`，并且必须为改变后的 ROM/SRAM 几何同步创建匹配链接脚本。

此路径不能用于已交付客户的应用更新；产品必须使用 `.omcu → UART → User Flash`。
