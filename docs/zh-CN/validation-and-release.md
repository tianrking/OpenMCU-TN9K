# 验证状态与发布门槛

> 本页明确区分“源代码可构建”“FPGA 已完成布局布线”“真板硬件在环”和“可量产交付”。它们不是同一件事，也不能互相替代。

## 当前结论（2026-08-25）

| 层级 | 状态 | 已获得的证据 | 仍缺少的证据 |
| --- | --- | --- | --- |
| 源码与协议回归 | 已通过 | RTL 冒烟、镜像格式、串口下载协议、Boot ROM 固件夹具检查 | 真板串口波形与异常恢复 |
| SDK 构建 | 已通过 | Bootloader、示例应用、`.omcu` 镜像均可由 RISC-V 工具链生成 | 客户操作系统上的安装与下载器兼容性 |
| FPGA 产品版布局布线 | 已通过 | Tang Nano 9K `GW1NR-LV9QN88PC6/I5` 完成综合、布局、布线、打包和时序检查 | 下载到实物板后的冷启动与外设行为 |
| User Flash A/B 更新 | 待真板验证 | RTL、镜像协议、下载器和仿真覆盖已具备 | 实际 `FLASH608K` 擦写、断电恢复、寿命和温度测试 |
| 面向量产的安全启动 | 未实现 | 当前 CRC32 可发现传输/存储损坏 | 签名验签、密钥保护、调试锁定、反回滚和安全生产流程 |

因此，当前仓库可以作为**可综合、可生成产品 `.fs`、可独立生成并下载 MCU 应用的工程基线**。在宣称“可交付客户硬件”或“量产可用”之前，必须完成下方的硬件在环（HIL）门槛。

## 本次已通过的构建与回归

以下命令在仓库根目录执行。`OMCU_IVERILOG_BIN` 指向已安装的 Icarus Verilog；其余命令由仓库脚本定位或接收显式工具链路径。

```powershell
$env:OMCU_IVERILOG_BIN = 'C:\ProgramData\chocolatey\lib\iverilog\tools\bin'

.\scripts\generate-sdk.ps1 -Check
.\scripts\check-tangnano9k-project.ps1 -McuMode

'user-flash', 'system', 'system-uart', 'sdk-isa', 'sdk-peripherals', `
  'sdk-i2c', 'sdk-irq', 'tn9k-wdt', 'tn9k-peripherals', 'tn9k', 'mcu-top' |
  ForEach-Object { .\scripts\run-rtl-smoke.ps1 -Test $_ }

python -m unittest `
  tools.tests.test_omcu_bootloader_fixture `
  tools.tests.test_omcu_image `
  tools.tests.test_omcu_flash_protocol -v
```

其中 `omcu_bootloader_fixture` 会把 SDK 刚生成的 `omcu_bootloader.hex` 与 FPGA 产品顶层默认引用的 `rtl/platform/tangnano9k/firmware/bootloader.hex` 逐个十六进制字比较。它允许换行格式和注释不同，但一旦真实指令内容漂移就会令构建失败，避免“SDK 已更新，固化在 FPGA 内的 Boot ROM 却仍是旧版本”。

SDK 构建也会自动执行这项检查：

```powershell
.\scripts\build-sdk.ps1
```

已生成的镜像示例为 `build/sdk/omcu_mcu_blink.omcu`；其头部 ABI 是 `0x00000005`。实际尺寸由链接结果决定，示例远小于 A/B 槽的单槽最大有效载荷 **36,800 字节**。

## FPGA 产品版布局布线记录

本次构建的是 MCU 产品顶层 `omcu_tn9k_mcu_top`，而不是旧的 bring-up 顶层：

```powershell
.\scripts\build-tangnano9k-open.ps1 -McuMode `
  -ToolBin <YowaspGowinToolBin> `
  -BuildDirectory .\build\tangnano9k-mcu-verify
```

结果如下：

| 项目 | 结果 |
| --- | --- |
| 输出文件 | `build/tangnano9k-mcu-verify/omcu_tn9k_mcu.fs` |
| SHA-256 | `1869a8d66a11970a35602d2826a7ef0838a05498467f9d7b9a4216830927b3c2` |
| 时钟约束 / 实现频率 | 27.000 MHz / 40.190 MHz |
| 时序余量 | 12.155 ns |
| LUT4 | 6,594 / 8,640（76.32%） |
| DFF | 1,758 / 6,480（27.13%） |
| BSRAM | 26 / 26（100.00%） |
| IOB | 15 / 276（5.43%） |
| Boot ROM / SRAM | 8 KiB / 44 KiB |
| User Flash | 76 KiB，2 个 A/B 槽，每槽最大应用 36,800 字节 |

该 `.fs` 的配置内容仅包含稳定的硬件平台和 8 KiB Boot ROM；客户的 `.omcu` 应用不再参与 FPGA 布局布线，也不需要重新生成 `.fs`。

`program-tangnano9k.ps1` 已用 `-WhatIf` 通过产品工件清单、SHA-256 与板型校验。它只证明主机端会调用正确的下载命令，**不代表实物 FPGA 已下载成功**。在真板通过后，才可使用去掉 `-WhatIf` 的命令。

### 历史 bring-up 记录（仅供审计）

早期 v0.4 的 `omcu_irq_smoke`、`omcu_tn9k_board_demo` 和 `omcu_peripheral_smoke` 曾分别生成过不同的 bring-up `.fs`。下表保留其 ROM 输入、BRAM 初始化指纹和位流哈希，便于追溯“不同 ROM 确实进入了旧 FPGA 构建”；它们不是当前 MCU 产品顶层的实现证据，也不能代替上表的产品版 `.fs`。

| SDK ROM | 输入 SHA-256 | 综合/P&R BSRAM 初始化指纹 | `.fs` SHA-256 |
| --- | --- | --- | --- |
| `omcu_irq_smoke` | `1409af0b9d1a1498520e6378752a2959c7d58979a4d5f0c232fa5bdd253d0b4d` | `173d1cf6c36fc89aedc62a7e5bff39cb255e064d2bfccaa616ec0bc604295c82` | `71e660f93b7ff190adfebffc697944b03c5175309f7bb5523a811448de5f5395` |
| `omcu_tn9k_board_demo` | `b35a525d571abe90fe034373e8108a4843544e78b59189cdeade8c3fab19bb30` | `291fd35b7018e0b5b45a3995793ed94b16811bf19569fec304d3238ec7172655` | `615ac5b62e9a84ab538cb9d831aaef3d668fb43370b569b5f7adfc4590c97e3a` |
| `omcu_peripheral_smoke` | `dbaf313dc1b12980e954665b799ea53578a31b1a1ea0d05a34961581c7f6acd7` | `4b1ecd0e29b6ae5ebfe9548d76193cf1ea17207f64a290e57b23b1c4acc3e86f` | `2f33fc5518a8fdedb1520aa185a115c68babf27421d7d6368fcb68b53f5f31e8` |

## 已知边界与警告

- 开源布局布线在现有 bring-up I2C/GPIO 三态路径上报告了一条 Yosys “tri-state logic support limited” 警告。产品位流仍已完成布局布线，但该路径必须纳入真板外设测试；不能把该警告解释为已被硬件验证。
- Icarus Verilog 对 `always_comb` 的常量位选和 `unique case` 会给出已知的功能限制提示；RTL 冒烟全部通过，但发布时仍应保留并审阅实际仿真日志。
- `FLASH608K` 的仿真替身只用于让产品顶层的控制路径参与 RTL 回归；它不是高云 User Flash 的行为模型。实际擦写时序、掉电语义和寿命只以实板测试及芯片厂商资料为准。
- 当前使用 CRC32 做镜像完整性检查、A/B 回退和提交原子性控制。CRC32 不具备来源认证能力，不能防止恶意替换镜像。
- 首版没有“应用软件请求跳回 Bootloader”的命令。标准恢复方式是在下载器连接期间复位板卡；若无可启动镜像，Bootloader 会持续等待串口下载。

## 真板硬件在环（HIL）发布门槛

### 1. FPGA 平台固化

1. 用 `sram` 方式下载产品 `.fs`，验证时钟、UART、LED 和复位工作正常。
2. 用板卡支持的非易失方式写入 FPGA 配置，断电至少 10 次后确认每次都能进入 Bootloader。
3. 记录板卡批次、FPGA 器件丝印、供电电压、下载器版本、`.fs` SHA-256 和操作日志。

### 2. MCU 应用更新和启动

1. 空白 User Flash：主机连接、`HELLO`、完整写入 `.omcu`、`BOOT`，确认示例应用运行。
2. 正常升级：连续交替写 A/B 两槽，确认 Bootloader 总是选择序号最新且 CRC 合法的已提交槽。
3. 故障镜像：分别验证错误 ABI、错误头 CRC、错误载荷 CRC、超长镜像和乱序包均被拒绝，旧应用仍可启动。
4. 中断升级：在擦除、数据页写入、`END` 校验、最终提交四个阶段分别断电；重新上电后必须只启动上一个完整镜像或等待恢复，绝不能跳转到半写入镜像。
5. 重复与重连：重复 `DATA`、重复 `END`、串口超时和主机重启后都要可安全恢复；下载器重试不得破坏已提交槽。

### 3. 接口与长期可靠性

1. 确认 UART0 的电平、接地、波特率 115200 8N1、USB 转串口芯片以及复位操作方式。
2. 验证 GPIO、I2C、SPI、PWM、看门狗和中断等目标产品会用到的外设。
3. 在目标温度、电压和电磁环境下做重复升级与冷启动测试；擦写次数以高云器件规格及实测结果制定保守寿命限制。
4. 建立失败日志、可追溯的 `.omcu` SHA-256、Bootloader 版本和板级序列号记录。

## 提交与发布卫生

每次对外发布前，保存通过的 Git commit、SDK `.omcu`、产品 `.fs`、manifest、SHA-256、完整工具版本、P&R 报告（包括 warning）和对应真板记录。提交前至少执行：

```powershell
git status --short
git diff --check
git ls-files | Select-String -Pattern '(?i)(\.fs$|\.bit$|\.elf$|\.hex$|\.vcd$)'
```

第二个命令应无输出。第三个命令只应找到有意提交的手写测试 ROM fixture；不应包含生成位流、私钥、token、`.env`、客户网络信息或受限的第三方 IP。推送后，以远端最终 commit 的 CI 结果作为 CI 通过证据，而不是以本机终端输出替代。

## 量产前仍需补齐的安全设计

如果设备会连接不可信网络、承担门禁/支付/工业控制等安全责任，下面工作不是可选项：

1. 用公钥签名验证替代“仅 CRC32 接受镜像”；CRC 可保留作误码检测。
2. 把信任根、版本策略和验签 Bootloader 放入受保护的不可变区域，并评审密钥注入流程。
3. 限制或锁定量产调试接口，设计恢复权限、反回滚与丢失设备后的处置方式。
4. 对更新协议做威胁建模、模糊测试和第三方安全评审。

在这些工作完成前，本工程应定位为面向教学、原型和受控环境的 FPGA MCU 平台，而不是“已具备安全启动的量产芯片”。
