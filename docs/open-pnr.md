# Tang Nano 9K 开源综合、布局布线与打包

<code>scripts/build-tangnano9k-open.ps1</code> 可从可移植 OpenMCU RTL 与 Tang Nano 9K 封装生成 FPGA 配置镜像。它有意采用开源实现链，因此第三方无需安装 GOWIN EDA 许可证也能复现构建产物：

~~~text
SystemVerilog -> Yosys synth_gowin -> nextpnr-himbaechel-gowin -> gowin_pack -> .fs
~~~

目标固定为开发板的 <code>GW1NR-LV9QN88PC6/I5</code> 封装和 <code>GW1N-9C</code> 器件家族。综合前，脚本检查 <code>.gprj</code> 是否包含 <code>rtl/files.f</code> 中全部源文件、Tang 封装、恰好一份 CST 和恰好一份 SDC；不会依赖 IDE 悄悄遗漏新外设。

## 产品模式：一次固化平台，之后独立升级应用

> **这是客户交付的默认路径。**
>
> <code>-McuMode</code> 产生的平台位流只包含稳定硬件、不可变 Boot ROM 启动器和 User Flash 控制器。客户应用始终以独立 <code>.omcu</code> 镜像经 UART0 写入 User Flash A/B 槽，绝不通过 <code>RomInitFile</code> 编进 FPGA 位流。

先初始化单独授权的 CPU 源码：

~~~powershell
git submodule update --init --recursive
~~~

已记录的软件包版本位于 <a href="../toolchains/yowasp-gowin.lock.json">toolchains/yowasp-gowin.lock.json</a>。Windows 建议使用 64 位 Python 3.10 或更新版本：固定的 Apycula 依赖在当前 Python 版本提供预编译 <code>fastcrc</code> wheel，而 Python 3.9 可能尝试在本机编译该 Rust 扩展。可用以下方式创建隔离环境：

~~~powershell
python -m venv .venv\yowasp-gowin
.\.venv\yowasp-gowin\Scripts\python -m pip install yowasp-yosys==0.68.0.0.post1208 yowasp-nextpnr-himbaechel-gowin==0.11.1.0.post826 apycula==0.32
$tools = (Resolve-Path .\.venv\yowasp-gowin\Scripts).Path
.\scripts\build-tangnano9k-open.ps1 -McuMode -ToolBin $tools -BuildDirectory .\build\tangnano9k-mcu
~~~

产品模式输出包括：

- <code>omcu_tn9k_mcu.json</code>：综合后的 Gowin JSON 网表；
- <code>omcu_tn9k_mcu_pnr.json</code>：布局布线后的网表；
- <code>omcu_tn9k_mcu_report.json</code>：时钟和资源报告；
- <code>omcu_tn9k_mcu.fs</code>：可下载 FPGA 配置镜像；
- <code>omcu_rom_image.hex</code>：由 Bootloader 生成的稠密 Boot ROM 镜像；
- <code>omcu_tn9k_mcu_manifest.json</code>：工具版本、ROM 初始化链、User Flash 几何、位流 SHA-256、时序与资源统计。

应用团队随后通过 <a href="../tools/omcu_image.py">omcu_image.py</a> 打包 <code>.omcu</code>，并通过 <a href="../tools/omcu_flash.py">omcu_flash.py</a> 串口更新；完整协议见 <a href="zh-CN/mcu-firmware-update.md">独立 MCU 固件开发与升级</a>。

## 开源实现链的可复现性

每次构建会把稀疏输入 <code>.hex</code> 转换为精确尺寸、以 RISC-V NOP 填充的 <code>omcu_rom_image.hex</code>，并在 Yosys 读取拥有 Boot ROM 的模块时，把该镜像作为字面 <code>$readmemh</code> 输入。这样做是刻意的：在解析后改字符串参数，不能作为存储器初始化已改变的证据。

脚本会记录稀疏 SDK 输入哈希、稠密有效镜像哈希，以及四个 Boot ROM BSRAM 单元在综合前后与 P&R 后的确定性指纹。如果两处 BSRAM 指纹不一致，构建失败。<code>-RomKiB</code>/<code>-SramKiB</code> 仅用于受控实验；其中任一项变化时，固件必须使用匹配的链接脚本。

输出必须位于仓库内的 <code>build/</code>，因为 YoWASP WebAssembly 可执行文件使用相对工程路径。脚本在以下任何条件下失败：综合、布局布线或打包失败；预期产物缺失；报告没有恰好一个时钟；或实际频率低于约束。生成文件均被 Git 忽略，因为它们是可复现构建输出而非事实来源。

## 已记录的产品模式 P&R 结果

以下记录来自 2026-08-25 生成的 <code>build/tangnano9k-mcu-verify/omcu_tn9k_mcu_manifest.json</code>：

| 项目 | 已记录结果 |
| --- | --- |
| 顶层 / 器件 | <code>omcu_tn9k_mcu_top</code> / <code>GW1NR-LV9QN88PC6/I5</code> |
| Boot ROM / SRAM | 8 KiB / 44 KiB |
| User Flash | 77,824 B（76 KiB），2 × 36,864 B 槽，单镜像最大载荷 36,800 B |
| Boot ROM 嵌入 | 4 个 BSRAM 单元，综合与 P&R 指纹一致 |
| 时钟 | 27.000 MHz 约束；40.189697 MHz 实现；12.155038 ns 裕量 |
| LUT4 | 6,594 / 8,640（76.32%） |
| DFF | 1,758 / 6,480（27.13%） |
| BSRAM | 26 / 26（100%） |
| ALU / MULT36X36 / IOB | 1,276 / 6,480；1 / 5；15 / 276 |
| 打包位流 SHA-256 | <code>1869a8d66a11970a35602d2826a7ef0838a05498467f9d7b9a4216830927b3c2</code> |

该记录证明开源实现链能够为精确目标器件完成产品模式的综合、P&R 与打包，并且 ROM 初始化链可追溯。它不是实体板下载或电气功能验证。

## 历史 bring-up 回归路径

默认的非 <code>-McuMode</code> 路径使用最小 LED 固件夹具。它仍用于 RTL、编译器和 P&R 回归，可以把 SDK 固件放进 FPGA Boot ROM；这不是客户更新接口。

例如，以下过程选择旧的板卡演示，不需修改 RTL：

~~~powershell
cmake -S sdk -B build/sdk -G Ninja -DCMAKE_TOOLCHAIN_FILE=sdk/cmake/riscv32-gcc.cmake -DOMCU_RISCV_PREFIX=riscv-none-elf-
cmake --build build/sdk --target omcu_tn9k_board_demo
.\scripts\build-tangnano9k-open.ps1 -ToolBin $tools -RomInitFile .\build\sdk\omcu_tn9k_board_demo.hex
~~~

<code>RomInitFile</code> 必须是仓库内已存在的文件。两条早期 ROM 选择记录保留为历史证据；它们使用相同器件、存储器几何和开源工具链，但不能替代 ABI 0.5 MCU 产品模式的结果。

| SDK Boot ROM | 输入 ROM SHA-256 | BSRAM 初始化指纹（综合 = P&R） | 打包 <code>.fs</code> SHA-256 |
| --- | --- | --- | --- |
| <code>omcu_irq_smoke</code>（历史 ABI 0.4） | <code>1409af0b9d1a1498520e6378752a2959c7d58979a4d5f0c232fa5bdd253d0b4d</code> | <code>173d1cf6c36fc89aedc62a7e5bff39cb255e064d2bfccaa616ec0bc604295c82</code> | <code>71e660f93b7ff190adfebffc697944b03c5175309f7bb5523a811448de5f5395</code> |
| <code>omcu_tn9k_board_demo</code> | <code>b35a525d571abe90fe034373e8108a4843544e78b59189cdeade8c3fab19bb30</code> | <code>291fd35b7018e0b5b45a3995793ed94b16811bf19569fec304d3238ec7172655</code> | <code>615ac5b62e9a84ab538cb9d831aaef3d668fb43370b569b5f7adfc4590c97e3a</code> |
| <code>omcu_peripheral_smoke</code> | <code>dbaf313dc1b12980e954665b799ea53578a31b1a1ea0d05a34961581c7f6acd7</code> | <code>4b1ecd0e29b6ae5ebfe9548d76193cf1ea17207f64a290e57b23b1c4acc3e86f</code> | <code>2f33fc5518a8fdedb1520aa185a115c68babf27421d7d6368fcb68b53f5f31e8</code> |

历史 ABI 0.4 行直接证明中断 SDK 固件可进入初始化 BSRAM 和最终 FPGA 镜像。不同历史源镜像、BSRAM 指纹和打包位流哈希也证明了 ROM 的真实选择，而不仅是记录了期望输入路径。详细历史证据见 <a href="validation.md">验证门禁与证据</a>。

Yosys 对顶层 I2C 与 GPIO Pad 适配器报告了其已知的受限三态支持警告。P&R 和打包仍完成；警告保留在 <code>yosys.log</code> 中，不得宣称为“零警告签核”。

## 下载与证据边界

本流程证明为精确器件准备好了可实现的 <code>.fs</code> 构建产物。它 **不** 证明已成功下载到开发板，也不证明 USB 上电、复位行为、LED 极性、UART 电气行为或任何特定 GOWIN EDA 版本兼容性；这些仍是实体板发布门禁。

安全的主机侧下载使用 <a href="../scripts/program-tangnano9k.ps1">scripts/program-tangnano9k.ps1</a>。该脚本会核对 <code>.fs</code> 与相邻 manifest 的 SHA-256，默认下载到易失 SRAM。持久写入配置 Flash 必须同时给出 <code>-Destination flash</code> 与 <code>-ConfirmFlash</code>；工具退出码成功仍不等于功能板验证。
