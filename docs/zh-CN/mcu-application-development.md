# 从零开发与烧录 OpenMCU 应用

> **客户应用的唯一日常流程：**编写 C 源码 → 编译为 `*.omcu` → 通过 UART0 写入 User Flash。
> 不修改 Verilog、不重新生成 FPGA 位流、不使用 FPGA 下载器写入客户业务程序。

本指南面向已经固化 `omcu_tn9k_mcu.fs` 产品位流的设备。产品位流包含固定的 4 KiB Boot ROM
启动器；客户程序独立保存于 User Flash 的 A/B 槽，并在启动时装入 40 KiB 应用 SRAM 运行。

```mermaid
flowchart LR
  C[裸机 C 源码] --> ELF[RV32IM ELF]
  ELF --> BIN[原始 SRAM 二进制]
  BIN --> IMG[带 CRC 的 .omcu]
  IMG -->|UART0 115200 8N1| BOOT[固定 Bootloader]
  BOOT --> FLASH[User Flash A/B]
  FLASH -->|复位、校验、复制| SRAM[40 KiB 应用 SRAM]
```

## 1. 开始前确认

| 项目 | 要求 |
| --- | --- |
| FPGA 平台 | 已烧录 `omcu_tn9k_mcu.fs` 产品位流；不是仅用于 RTL 验证的开发位流。 |
| MCU 应用语言 | 当前经过构建链验证的是裸机 **C**；不要把 C++ 运行库、异常或动态分配当作已支持能力。 |
| CPU ABI | `rv32im` / `ilp32`，硬件 ABI `0x00000009`；不支持压缩指令 `C`。 |
| 下载线 | Tang Nano 9K 板载 BL702 USB-UART，`115200 / 8-N-1`；通常只需连接板上 USB-C，不需要再接排针跳线。 |
| UART0 位置 | 顶层网络为 `uart_tx_o` / `uart_rx_i`，FPGA package pad 为 17 / 18，PCB 已连接到 BL702；macOS 通常枚举为 `/dev/cu.usbserial-*`，Windows 为 `COM*`。派生板若直接引出这两个 pad，才按 3.3 V TTL、TX/RX 交叉、共地连接，不能接 RS-232 电平。 |
| 存储上限 | 单个 `.omcu` 载荷最多 36,800 B；代码、数据、栈和中断帧共享 40 KiB 应用 SRAM。 |

UART0 同时是更新和默认日志通道。烧录工具与串口终端不能同时打开同一端口。

## 2. 主机环境

需要安装：Git、CMake 3.20 或更新版本、Ninja、Python 3，以及 GNU bare-metal RISC-V
工具链。只在串口烧录时额外需要 `pyserial`。

工具链使用 `riscv-none-elf-` 可执行前缀；推荐 xPack GNU RISC-V Embedded GCC `15.2.0-1`。
Windows 归档地址和 SHA-256 由仓库的
[工具链锁定文件](../../toolchains/riscv-none-elf-gcc-15.2.0-1.lock.json)固定。安装后必须能找到
`riscv-none-elf-gcc` 与 `riscv-none-elf-objcopy`。

若还需要构建或固化 FPGA 平台，或希望从零安装 Windows、Ubuntu 和 macOS 的完整锁定工具链，请先读
[《Windows、Ubuntu 与 macOS 的 FPGA / MCU 开发环境》](cross-platform-fpga-development.md)。本页只保留客户 MCU 应用开发所需步骤。

### Windows

以下命令以 PowerShell 为例。把 `$toolBin` 改为实际包含两个 `.exe` 文件的目录：

```powershell
Set-Location F:\OpenMCU-TN9K
git submodule update --init --recursive

$toolBin = 'C:\toolchains\riscv-none-elf\bin'
$env:PATH = "$toolBin;$env:PATH"

cmake --version
ninja --version
riscv-none-elf-gcc --version
riscv-none-elf-objcopy --version

.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
```

若 CMake 或 Ninja 不在 `PATH`，可向脚本额外传入 `-Cmake <绝对路径>`、`-Ninja <绝对路径>`。
`-Fresh` 只清理指定 SDK 构建目录，要求 CMake 3.24 或更新版本。

### Ubuntu / Linux

以 Debian/Ubuntu 为例，先安装主机工具，再将同版本 xPack 工具链的 `bin` 加入 `PATH`：

```sh
sudo apt-get update
sudo apt-get install -y git cmake ninja-build python3 python3-venv

cd ~/OpenMCU-TN9K
git submodule update --init --recursive

export PATH="/opt/xpack-riscv-none-elf/bin:$PATH"
riscv-none-elf-gcc --version
riscv-none-elf-objcopy --version

sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
```

串口设备通常为 `/dev/ttyUSB0` 或 `/dev/ttyACM0`。若出现权限错误，Debian/Ubuntu 通常需要执行
`sudo usermod -aG dialout "$USER"`，然后注销并重新登录；其他发行版的串口用户组名称可能不同。

### macOS

macOS 使用与 Linux 相同的 SDK 构建脚本。先安装 Homebrew、Git、CMake、Ninja、Python、Node.js 和
`riscv-none-elf-` 工具链；锁定版 xpm 工具链和完整安装命令见[跨平台开发环境](cross-platform-fpga-development.md)。

```sh
cd ~/OpenMCU-TN9K
git submodule update --init --recursive

export PATH="/实际/xpack-riscv-none-elf/bin:$PATH"
riscv-none-elf-gcc --version
riscv-none-elf-objcopy --version

sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
```

应用 UART 端口通常形如 `/dev/cu.usbserial-XXXX`。先用 `ls /dev/cu.*` 查到实际端口；不要使用同一设备的
`/dev/tty.*` 名称替代 `cu.*`，也不要让串口终端与下载器同时占用端口。

## 3. 先构建并烧录官方 Hello World

仓库自带一个独立 MCU 应用：[`omcu_mcu_hello`](../../sdk/examples/mcu_hello/main.c)。它每隔一段时间在
UART0 输出 `Hello, OpenMCU-TN9K!`，并生成可日常烧录的 `.omcu`，不是 FPGA ROM 输入。

Windows：

```powershell
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-

python .\tools\omcu_image.py validate `
  --image .\build\sdk\omcu_mcu_hello.omcu
python .\tools\omcu_image.py inspect `
  --image .\build\sdk\omcu_mcu_hello.omcu
```

Linux：

```sh
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-

python3 ./tools/omcu_image.py validate \
  --image ./build/sdk/omcu_mcu_hello.omcu
```

macOS：

```sh
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-

python3 ./tools/omcu_image.py validate \
  --image ./build/sdk/omcu_mcu_hello.omcu
```

构建产物位于 `build/sdk/`：

| 文件 | 用途 |
| --- | --- |
| `omcu_mcu_hello.elf` | 调试、反汇编和 map 分析。 |
| `omcu_mcu_hello.bin` | 原始 SRAM 载荷。 |
| `omcu_mcu_hello.omcu` | **唯一应交给下载器的客户应用镜像。** |

## 4. 写自己的应用

推荐把客户业务代码放在 OpenMCU 仓库之外。复制完整模板，而不是修改 SDK 的示例清单：

macOS / Linux：

```sh
cp -R /path/to/OpenMCU-TN9K/templates/omcu-app ~/my-omcu-app
cd ~/my-omcu-app
export OMCU_SDK_PATH=/path/to/OpenMCU-TN9K/sdk
export PATH=/path/to/riscv-none-elf/bin:$PATH
./build.sh
```

Windows PowerShell：

```powershell
Copy-Item -Recurse C:\src\OpenMCU-TN9K\templates\omcu-app C:\src\my-omcu-app
Set-Location C:\src\my-omcu-app
$env:OMCU_SDK_PATH = 'C:\src\OpenMCU-TN9K\sdk'
$env:PATH = "C:\toolchains\riscv-none-elf\bin;$env:PATH"
.\build.ps1
```

模板的 `CMakeLists.txt` 只声明自己的源码，并引用公开 SDK 模块：

```cmake
include("${OMCU_SDK_PATH}/cmake/OpenMCUSDK.cmake")
omcu_add_application(my_omcu_app src/main.c)
```

生成物位于客户工程自己的 `build/`：`my_omcu_app.elf`、`.map`、`.bin` 与 `.omcu`。需要外置器件
驱动时增加 `target_link_libraries(my_omcu_app PRIVATE OpenMCU::device_drivers)`。

`omcu_add_application()` 会自动选择正确的启动代码、链接脚本、`rv32im` / `ilp32` 编译参数、
ELF 到 BIN 转换及 `.omcu` 的 CRC 封装。应用开发者不应手写镜像头，也不应把应用源码加入 FPGA
位流构建输入。

模板脚本每次只构建该应用并调用 `omcu_image.py validate`。若直接使用 CMake，等效命令是：

```sh
cmake -S . -B build -G Ninja \
  -DOMCU_SDK_PATH="$OMCU_SDK_PATH" \
  -DOMCU_RISCV_PREFIX=riscv-none-elf-
cmake --build build --target my_omcu_app --parallel
```

## 5. 通过 UART0 烧录

安装一次主机端依赖。Windows：

```powershell
python -m pip install pyserial
.\flash.ps1 -Port COM5
```

Linux 建议放入虚拟环境：

```sh
mkdir -p ~/.venvs
python3 -m venv ~/.venvs/openmcu-host
. ~/.venvs/openmcu-host/bin/activate
python -m pip install pyserial
./flash.sh /dev/ttyUSB0
```

macOS 同样建议放入虚拟环境：

```sh
mkdir -p ~/.venvs
python3 -m venv ~/.venvs/openmcu-host
. ~/.venvs/openmcu-host/bin/activate
python -m pip install pyserial
./flash.sh /dev/cu.usbserial-XXXX
```

这些模板脚本调用 SDK 仓库中的 `tools/omcu_flash.py`，并选择客户工程自己的
`build/my_omcu_app.omcu`。

将 `COM5`、`/dev/ttyUSB0` 或 `/dev/cu.usbserial-XXXX` 换为系统实际串口。下载器默认在 8 秒内反复发送 `HELLO`；运行命令后，
如果板子正在运行应用，按一次外部复位键。它会擦除非当前槽中新镜像实际占用的页、传输、回读 CRC、原子提交并默认启动新应用。

如果只想写入但暂不启动，增加 `--no-boot`；之后外部复位会按正常规则启动最新已提交镜像。

下载完成、工具退出后，才能打开串口终端查看 Hello World：

```powershell
python -m serial.tools.miniterm COM5 115200
```

```sh
python -m serial.tools.miniterm /dev/ttyUSB0 115200
```

```sh
python -m serial.tools.miniterm /dev/cu.usbserial-XXXX 115200
```

打开终端后按复位键，应持续看到 `Hello, OpenMCU-TN9K!`。若没有输出，先确认板级 UART0 连接、
3.3 V 电平、TX/RX 方向、共地和端口占用情况。

### 5.1 UART0 双向回显验收

仓库提供只访问板载 UART0 的 `omcu_mcu_uart_echo`，不会驱动六线回环夹具中的 GPIO。构建并烧录：

```sh
cmake --build build/sdk --target omcu_mcu_uart_echo --parallel
python3 tools/omcu_flash.py \
  --port /dev/cu.usbserial-XXXX \
  --image build/sdk/omcu_mcu_uart_echo.omcu
```

先打开 115200 8N1 终端再按一次板上复位键；Bootloader 的短监听窗口结束后应看到
`OMCU_UART0_ECHO_READY`，之后键盘发送的每个字节应原样返回。
UART0 只有单字节 RX 寄存器而没有 FIFO，压力测试应同时检查 `RX_OVERRUN`，不能把终端逐字节通过
外推成任意波特率、任意长时间屏蔽中断都不会丢数据。

## 6. 正常迭代与恢复

每次迭代只需：编辑 C 源码 → 构建 `.omcu` → 串口烧录。FPGA 配置保持不变。

若业务程序长期占用 UART0，可在安全结束关键写入、关闭受控输出后请求进入 Bootloader：

```c
#include "omcu_tn9k.h"

if (omcu_tn9k_request_bootloader()) {
  for (;;) {
  }
}
```

该调用会请求 SoC 复位，并保持 UART0 更新会话；成功后不要依赖后续业务代码继续运行。外部复位仍是
必须保留的独立恢复入口。

| 现象 | 首先检查 |
| --- | --- |
| 找不到 Bootloader | 是否为产品位流；UART0 是否接对；先启动工具再按复位。 |
| 镜像被拒绝 | 用当前 SDK 重建；不要手工修改 `.omcu`。 |
| 更新时断电 | 复位后旧的已提交 A/B 槽应仍可启动；重新烧录新镜像。 |
| 两个槽均无效 | Bootloader 会持续监听 UART；重新传一个校验通过的 `.omcu`。 |
| FPGA 不能启动 | 这是 FPGA 配置或板级问题，使用平台/工厂流程恢复 `.fs`，不是应用烧录问题。 |

## 7. 重要边界

- 单个应用最多 36,800 B，且运行时的代码、全局数据、栈和中断帧共同占用 40 KiB SRAM。
- CRC32 用于防传输损坏与断电一致性，不是签名安全启动。
- 用户应用只能通过 Bootloader 管理 A/B 槽；不要直接改写 active/fallback 槽。
- 当前仓库的 SDK、镜像协议和 P&R 已有自动化验证；本次单板的板载 UART0、User Flash 正常 A/B 更新、应用启动、六线数字回环及 UART1 外置 FT232R 64 KiB 无错回显已完成 HIL。分阶段断电、电气波形、外置 I2C/SPI 目标、多板和长期可靠性仍须继续验收。

下一步按需阅读：[外设与 SDK](peripherals-and-sdk.md)、[硬件与引脚](hardware-and-pins.md)、
[中断开发约定](interrupts.md)和[完整外设与引脚规格书](peripheral-pin-specification.md)。
