# Windows、Ubuntu 与 macOS 的 FPGA / MCU 开发环境

> **结论：**Windows、Ubuntu 和 macOS 都可以配置 OpenMCU-TN9K 的 MCU 开发环境，以及基于开源工具的 FPGA RTL、综合、P&R、.fs 打包和 USB 下载环境。Windows 是本仓库当前产品 FPGA P&R CI 的已验证主机；Ubuntu 和 macOS 的工具链、命令与下载器可用，但在称为“该主机已实板验证”前，仍必须完成本页的本机构建与 SRAM HIL。

本页面严格区分两条链：

- **FPGA / 平台链**：RTL -> 综合/P&R -> <code>omcu_tn9k_mcu.fs</code> -> SRAM 或配置 Flash；
- **客户 MCU 链**：C -> RV32IM ELF/BIN -> <code>.omcu</code> -> UART0 -> User Flash A/B。

客户业务程序绝不重新编进 FPGA 位流，也不应使用 FPGA 下载器更新。

~~~mermaid
flowchart LR
  subgraph P[低频：FPGA 平台工程]
    RTL[SystemVerilog] --> PNR[YoWASP / nextpnr / gowin_pack]
    PNR --> FS[omcu_tn9k_mcu.fs]
    FS --> CFG[USB: SRAM / 配置 Flash]
  end
  subgraph A[高频：MCU 应用工程]
    C[C 裸机应用] --> ELF[RV32IM ELF / BIN]
    ELF --> IMG[独立 .omcu]
    IMG --> UART[UART0]
    UART --> UF[User Flash A/B]
  end
~~~

## 1. 三平台支持状态

| 主机 | MCU SDK | RTL / 编译固件仿真 | 产品 FPGA P&R / packing | USB 下载工具 | 实体板 HIL |
| --- | --- | --- | --- | --- | --- |
| Windows x64 | CI 已验证 | CI 已验证 | **CI 已验证** | openFPGALoader + 项目包装脚本 | 待实板 |
| Ubuntu x64 / arm64 | Ubuntu CI 已验证 | Ubuntu CI 已验证 | 工具与命令可配置；当前未作为项目 P&R CI 主机 | openFPGALoader 支持 | 待实板 |
| macOS Intel / Apple Silicon | macOS CI 已验证 | 可使用同一 pwsh 脚本 | 工具与命令可配置；当前未作为项目 P&R CI 主机 | openFPGALoader 支持 | 待实板 |

YoWASP 的 Python 工具官方支持 Linux x86_64/AArch64、macOS x86_64/AArch64 与 Windows x86_64；其 Gowin nextpnr 包依赖 Apycula 提供 <code>gowin_pack</code>。参见 [YoWASP 平台说明](https://yowasp.org/)。openFPGALoader 官方支持 Linux、Windows、macOS，且板卡支持表包含 <code>tangnano9k</code>。参见 [安装说明](https://trabucayre.github.io/openFPGALoader/guide/install.html) 与 [板卡支持表](https://trabucayre.github.io/openFPGALoader/compatibility/board.html)。

**不要混淆证据：**CI、仿真和 P&R 仅证明源码与工具链可构建；它们不证明某一台主机能访问 USB、某一块 Tang Nano 9K 已启动、配置 Flash 已可靠写入或外设电气正确。

## 2. 三种主机共同需要的工具

| 工具 | 用途 | 要求 |
| --- | --- | --- |
| Git | 克隆和子模块 | 必须初始化 PicoRV32 子模块 |
| Python 3.10+ | YoWASP、Apycula、镜像和串口工具 | 使用独立虚拟环境 |
| CMake 3.20+、Ninja | SDK、Boot ROM 和应用构建 | 必须可从 PATH 找到 |
| GNU RISC-V bare-metal GCC | 编译 RV32IM / ILP32 固件 | 必须包含 gcc 和 objcopy |
| Node.js 20+ / npm | xpm 获取锁定版 GCC | CI 使用 Node 22、xpm 0.23.2 |
| PowerShell 7（pwsh） | FPGA 构建、检查、下载包装脚本 | FPGA 链统一使用 pwsh |
| YoWASP / Apycula | Yosys、Gowin nextpnr、gowin_pack | 版本由 lock 文件固定 |
| openFPGALoader | Tang Nano 9K SRAM / 配置 Flash 下载 | 必须识别 tangnano9k |

本项目要求裸机 <code>riscv-none-elf-</code> 工具链。不要使用 Linux 用户态的 <code>riscv64-linux-gnu-gcc</code>，也不要混入缺少 <code>objcopy</code> 的编译器。

## 3. 克隆项目

三种系统均从仓库根目录开始：

~~~text
git clone https://github.com/tianrking/OpenMCU-TN9K.git
cd OpenMCU-TN9K
git submodule update --init --recursive
~~~

<code>build/</code>、<code>.venv/</code> 和 <code>.xpack-store/</code> 是本机生成目录，不能提交。

## 4. 安装基础工具

### 4.1 Windows 10/11 x64

推荐使用 **PowerShell 7**。若已启用 winget，可执行：

~~~powershell
winget install --exact --id Git.Git
winget install --exact --id Kitware.CMake
winget install --exact --id Ninja-build.Ninja
winget install --exact --id Python.Python.3.12
winget install --exact --id Microsoft.PowerShell
winget install --exact --id OpenJS.NodeJS.LTS
~~~

重新打开 PowerShell 7 后检查：

~~~powershell
git --version
python --version
cmake --version
ninja --version
node --version
npm --version
pwsh --version
~~~

Windows 上的 openFPGALoader 推荐通过 MSYS2 UCRT64 安装：

~~~text
# 在 MSYS2 UCRT64 终端执行：
pacman -Syu
pacman -S --needed mingw-w64-ucrt-x86_64-openFPGALoader
~~~

将 <code>C:\msys64\ucrt64\bin</code> 加入 Windows PATH，再在 PowerShell 中确认：

~~~powershell
openFPGALoader --version
openFPGALoader --list-boards | Select-String tangnano9k
~~~

若使用自行编译的下载器，项目脚本可传入 <code>-OpenFPGALoader &lt;绝对路径&gt;</code>。

### 4.2 Ubuntu 22.04 / 24.04

安装基础工具与发行包中的 openFPGALoader：

~~~sh
sudo apt-get update
sudo apt-get install -y git cmake ninja-build python3 python3-venv python3-pip nodejs npm openfpgaloader wget apt-transport-https software-properties-common
~~~

按 Microsoft 包仓库安装 PowerShell 7：

~~~sh
source /etc/os-release
wget -q "https://packages.microsoft.com/config/ubuntu/$VERSION_ID/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell

pwsh --version
openFPGALoader --version
openFPGALoader --list-boards | grep tangnano9k
~~~

<code>xpm@0.23.2</code> 需要 Node.js 20 或更新版本；Ubuntu 发行版自带的 Node.js 可能过旧。若 <code>node --version</code> 小于 v20，请按 [Node.js 官方 Linux 安装页](https://nodejs.org/en/download/package-manager) 安装当前 LTS（CI 使用 Node 22）后再运行第 5 节。

串口通常需要 <code>dialout</code> 权限；JTAG/FTDI 若被拒绝还可能需要 <code>plugdev</code> 或 udev 规则：

~~~sh
sudo usermod -aG dialout "$USER"
sudo usermod -aG plugdev "$USER" 2>/dev/null || true
~~~

注销并重新登录、重新插拔板卡后运行 <code>openFPGALoader --scan-usb</code>。仍无权限时，按 [openFPGALoader 的 Ubuntu udev 规则说明](https://trabucayre.github.io/openFPGALoader/guide/install.html) 配置；不要长期用 sudo 代替权限修复。

### 4.3 macOS（Intel 与 Apple Silicon）

安装 Homebrew 后，在 macOS Terminal 执行：

~~~sh
xcode-select --install
brew install git cmake ninja python node openfpgaloader
~~~

PowerShell 7 使用与 CPU 架构匹配的官方 macOS 包，然后检查：

~~~sh
pwsh --version
openFPGALoader --version
openFPGALoader --list-boards | grep tangnano9k
~~~

PowerShell 官方安装页同时提供 Arm64 与 x64 包：[安装 PowerShell 7（macOS）](https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-macos)。

锁定版 xpm GCC 为 Windows x64、Linux x64/arm64、macOS x64/arm64 提供对应主机二进制，因此 Apple Silicon 可使用原生 <code>darwin-arm64</code> 工具链；仍应执行第 5 节的版本检查，不要从另一台主机复制编译器目录。

应用 UART 端口通常使用 <code>/dev/cu.*</code>：

~~~sh
ls /dev/cu.*
~~~

例如实际端口可能是 <code>/dev/cu.usbserial-XXXX</code>。若 USB 下载器找不到板卡，先直连电脑 USB、避免无供电 Hub，并在“系统信息 -> USB”中确认 FTDI/FT2232 已被枚举。

## 5. 三种主机共用的锁定工具链

以下代码块必须在 **PowerShell 7（pwsh）** 中、仓库根目录执行。它与 CI 使用相同版本，xpm 缓存写入 Git 忽略的 <code>build/.xpack-store</code>，YoWASP 写入 Git 忽略的 <code>.venv/fpga</code>。

~~~powershell
$repo = (Get-Location).Path

# 1) 锁定版 YoWASP / Gowin nextpnr / Apycula。
$hostPython = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { 'python3' }
& $hostPython -m venv .venv/fpga
$venvDir = if ($IsWindows) { 'Scripts' } else { 'bin' }
$venvPythonName = if ($IsWindows) { 'python.exe' } else { 'python' }
$venvPython = Join-Path (Join-Path $repo '.venv/fpga') (Join-Path $venvDir $venvPythonName)
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install 'yowasp-yosys==0.68.0.0.post1208' 'yowasp-nextpnr-himbaechel-gowin==0.11.1.0.post826' 'apycula==0.32'
if ($LASTEXITCODE -ne 0) { throw 'YoWASP/Apycula installation failed.' }

$venvBin = Split-Path -Parent $venvPython
$env:PATH = "$venvBin$([IO.Path]::PathSeparator)$env:PATH"

# 2) 用 CI 同一版本的 xpm 获取 GNU RISC-V bare-metal GCC。
$env:XPACKS_STORE_FOLDER = Join-Path $repo 'build/.xpack-store'
$xpmWork = Join-Path $repo 'build/.xpm-work'
New-Item -ItemType Directory -Force -Path $xpmWork | Out-Null
Push-Location $xpmWork
try {
  npm install --no-save xpm@0.23.2
  $xpmName = if ($IsWindows) { 'xpm.cmd' } else { 'xpm' }
  $xpmPath = Join-Path $xpmWork (Join-Path 'node_modules/.bin' $xpmName)
  if (-not (Test-Path -LiteralPath (Join-Path $xpmWork 'package.json') -PathType Leaf)) {
    & $xpmPath init --name openmcu-local
    if ($LASTEXITCODE -ne 0) { throw "xpm init failed: $LASTEXITCODE" }
  }
  & $xpmPath install '@xpack-dev-tools/riscv-none-elf-gcc@15.2.0-1.1' --verbose
  if ($LASTEXITCODE -ne 0) { throw "xpm install failed: $LASTEXITCODE" }
} finally {
  Pop-Location
}

$compilerName = if ($IsWindows) { 'riscv-none-elf-gcc.exe' } else { 'riscv-none-elf-gcc' }
$compiler = Get-ChildItem -LiteralPath $env:XPACKS_STORE_FOLDER -Recurse -Force -File -Filter $compilerName | Select-Object -First 1
if ($null -eq $compiler) { throw "xPack did not provide $compilerName" }
$env:PATH = "$($compiler.DirectoryName)$([IO.Path]::PathSeparator)$env:PATH"

# 3) 所有项目工具的可用性检查。
foreach ($tool in @('cmake', 'ninja', 'riscv-none-elf-gcc', 'riscv-none-elf-objcopy', 'yowasp-yosys', 'yowasp-nextpnr-himbaechel-gowin', 'gowin_pack')) {
  Get-Command $tool -ErrorAction Stop | Out-Null
}
riscv-none-elf-gcc --version
yowasp-yosys --version
yowasp-nextpnr-himbaechel-gowin --version
~~~

该 PowerShell 会话会保留 PATH。新开终端后应重新执行本节，或将已验证的工具路径加入系统环境变量。

## 6. FPGA 平台：检查、构建和 P&R

### 6.1 不接触硬件的预检

~~~powershell
./scripts/generate-sdk.ps1 -Check
./scripts/check-tangnano9k-project.ps1 -McuMode
~~~

这会检查寄存器生成、RTL 清单、顶层与 Tang Nano 9K 约束；不生成位流，也不访问 USB。

### 6.2 构建 Boot ROM 与 SDK

Windows 使用 PowerShell 构建；Ubuntu/macOS 使用 shell 构建。两者生成相同 ABI 的 Boot ROM 和 SDK。

~~~powershell
if ($IsWindows) {
  ./scripts/build-sdk.ps1 -RiscvPrefix riscv-none-elf-
} else {
  sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
}
~~~

<code>build/sdk/omcu_bootloader.hex</code> 是 FPGA 内部 4 KiB Boot ROM 输入，不是客户应用。客户应用镜像是 <code>*.omcu</code>。

### 6.3 生成产品 FPGA 位流

~~~powershell
$toolBin = Split-Path -Parent (Get-Command yowasp-yosys -ErrorAction Stop).Source
./scripts/build-tangnano9k-open.ps1 -McuMode -ToolBin $toolBin -BuildDirectory build/tangnano9k-mcu
~~~

成功后应保留：

| 文件 | 用途 |
| --- | --- |
| <code>omcu_tn9k_mcu.fs</code> | Tang Nano 9K FPGA 配置位流 |
| <code>omcu_tn9k_mcu_manifest.json</code> | 器件、模式、资源、时序、ROM 指纹与 SHA-256 |
| <code>omcu_tn9k_mcu_report.json</code> | P&R 资源和时序报告 |
| <code>yosys.log</code>、<code>nextpnr.log</code> | 可追溯的综合和 P&R 日志 |

不要把业务应用 C 程序混入 .fs。正常客户升级仍是 <code>.omcu -> UART0 -> User Flash</code>。

## 7. FPGA 下载：先 SRAM，后配置 Flash

项目包装脚本会检查 .fs 对应 manifest、目标器件和 SHA-256。始终先 dry-run 和 SRAM：

~~~powershell
$fs = Join-Path $PWD 'build/tangnano9k-mcu/omcu_tn9k_mcu.fs'

# 只显示命令，不访问硬件。
./scripts/program-tangnano9k.ps1 -BitstreamPath $fs -WhatIf

# 易失下载；掉电后消失。
./scripts/program-tangnano9k.ps1 -BitstreamPath $fs -Destination sram
~~~

SRAM 下载后至少验证：时钟/复位、UART0 Bootloader 连接窗口、Hello World、GPIO/LED 基线以及本次修改的接口。记录主机系统与 CPU、Git 提交、工具版本、manifest SHA-256、板卡版本和结果。

仅在 SRAM 验证通过后，才可持久写 FPGA 配置 Flash：

~~~powershell
./scripts/program-tangnano9k.ps1 -BitstreamPath $fs -Destination flash -ConfirmFlash
~~~

这是配置 Flash 操作，不是 MCU 应用升级。供电必须稳定，不能在过程中拔线或断电；若下载失败，停在 SRAM 阶段排查，不要反复盲写 Flash。

## 8. MCU 应用：三种系统的构建与 UART0 烧录

固化产品 FPGA 位流后，日常应用工作只需 C -> .omcu -> UART0。应用模板和自定义目标见 [从零开发与烧录 OpenMCU 应用](mcu-application-development.md)。

### Windows

~~~powershell
./scripts/build-sdk.ps1 -RiscvPrefix riscv-none-elf-
python -m pip install pyserial
python ./tools/omcu_flash.py --port COM5 --image ./build/sdk/omcu_mcu_hello.omcu
python -m serial.tools.miniterm COM5 115200
~~~

将 COM5 改为设备管理器中的实际端口。下载器和串口终端不能同时打开它。

### Ubuntu

~~~sh
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
python3 -m venv ~/.venvs/openmcu-host
. ~/.venvs/openmcu-host/bin/activate
python -m pip install pyserial
python ./tools/omcu_flash.py --port /dev/ttyUSB0 --image ./build/sdk/omcu_mcu_hello.omcu
python -m serial.tools.miniterm /dev/ttyUSB0 115200
~~~

端口也可能是 <code>/dev/ttyACM0</code>；权限失败时检查第 4.2 节的 dialout 配置。

### macOS

~~~sh
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
python3 -m venv ~/.venvs/openmcu-host
. ~/.venvs/openmcu-host/bin/activate
python -m pip install pyserial

# 先用 ls /dev/cu.* 找到端口，再替换示例。
python ./tools/omcu_flash.py --port /dev/cu.usbserial-XXXX --image ./build/sdk/omcu_mcu_hello.omcu
python -m serial.tools.miniterm /dev/cu.usbserial-XXXX 115200
~~~

下载器默认约 8 秒寻找 Bootloader。板子正在运行应用时，先启动下载命令再按一次复位键；应用复用 UART0 时，可在安全收尾后调用 <code>omcu_tn9k_request_bootloader()</code>。

## 9. 常见问题

| 现象 | 优先检查 | 不应做的事 |
| --- | --- | --- |
| 找不到 pwsh | 安装 PowerShell 7；确认 pwsh --version | 认为旧 Windows PowerShell 与跨平台 pwsh 等价 |
| 找不到 YoWASP 或 gowin_pack | 重跑第 5 节，确认虚拟环境 bin/Scripts 在 PATH | 混用系统其他版本 Yosys |
| 找不到 RISC-V GCC | 检查 xpm 缓存和 PATH | 改用 riscv64-linux-gnu-gcc |
| Boot ROM .hex 缺失 | 先执行第 6.2 节 | 复制旧 .hex 或塞入客户应用 |
| 下载器找不到板 | 直连 USB、scan-usb、检查 Ubuntu 规则/组权限 | 反复写配置 Flash |
| UART 无响应 | 3.3 V TTL、TX/RX 交叉、共地、端口未占用、先启动工具再复位 | 用 FPGA 下载器替代 .omcu 升级 |
| P&R 成功但板无输出 | 检查实际 SRAM 下载、接线、电源、复位、电平和板卡版本 | 把 P&R 成功当成 HIL 通过 |

## 10. 交接前必须保留的证据

每次更改 FPGA 平台至少保存：

1. Git 提交与子模块提交；
2. 操作系统、CPU、Python、pwsh、YoWASP、xpm、RISC-V GCC、openFPGALoader 版本；
3. manifest、P&R 日志、资源/时序报告和 .fs SHA-256；
4. SRAM 下载、冷启动、UART0、A/B 应用更新和异常断电的实板记录；
5. 若写入配置 Flash，记录确认人、板卡序列号与恢复方式。

自动化构建与实体板 HIL 是不同证据层级。当前发布边界见 [验证与发布状态](validation-and-release.md)，引脚/电压/外设检查见 [硬件与引脚实验指南](hardware-and-pins.md)。
