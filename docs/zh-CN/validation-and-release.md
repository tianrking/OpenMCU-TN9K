# 验证状态与发布门槛

> **当前产品基线：** ABI `0.9`、`rv32im` / `ilp32`、4 KiB Boot ROM、44 KiB SRAM、76 KiB User Flash A/B。<br>
> **可追溯 FPGA 构建：** `build/tangnano9k-mcu-release-drain/`。<br>
> **结论：** RTL、SDK、独立客户工程、镜像工具、精确目标 P&R/packing、单板固化/User Flash 更新和无夹具核心自检已通过；固定跳线、外置目标器件、多板/长期可靠性、安全启动和量产资格尚未完成。

本页明确区分“源码存在”“数字仿真通过”“已生成目标位流”“实体板通过”和“可量产”。它们不能互相替代。对外发布时必须保存对应 Git commit、`.fs`、manifest、`.omcu`、工具版本与真实板记录。

## 1. 证据矩阵

| 层级 | 状态 | 已有证据 | 尚未覆盖 |
| --- | --- | --- | --- |
| 规格 / SDK 同步 | 已通过 + 仓库外构建/HIL | `generate-sdk.ps1 -Check`；独立模板从仓库外引用 `OpenMCUSDK.cmake`，生成/校验/实板烧录并运行 | 更多客户工程、IDE 与第三方工具链组合 |
| SDK / Boot ROM | 已通过 + 单板 HIL | 全量 SDK 以 `rv32im` 构建；已提交 Boot ROM fixture 与生成 `.hex` 逐 word 一致；2026-08-27 在一块 Tang Nano 9K 上从固化配置启动并完成 UART 更新 | 多板、反复冷启动与长期可靠性 |
| RTL / 集成仿真 | 已通过 | 36 个 smoke 目标，覆盖全部公开外设、CPU、SDK、User Flash 模型、Tang 顶层及新原子 MMIO 合同 | 真实电平、异步噪声、功率级和真实 Flash |
| 镜像 / 下载协议 | 已通过 + 正常路径 HIL | Python 单元测试 12/12；实体 UART 连续完成 A→B→A 更新、逐字回读、CRC、原子提交和 BOOT ACK | 丢包注入、各阶段断电和跨设备互操作 |
| FPGA 产品构建 | 已通过 + 单板 HIL | `GW1NR-LV9QN88PC6/I5` 综合、P&R、packing、ROM BSRAM 指纹和 manifest；SRAM 与配置 Flash 下载 CRC 均成功 | 至少 10 次断电冷启动、多板、电气与长期可靠性 |
| User Flash A/B | 单板正常路径已通过 | 实测擦除态 `0x00000000`、编程 `0→1`；空白恢复、A/B 轮换、回读 CRC 和应用启动通过 | 四阶段断电、擦写寿命、温度和损坏槽故障注入 |
| 核心/空载外设 HIL | 单板 24/24 通过 | WDT 真实复位、16 KiB SRAM、RV32IM、UART0 PING/PONG、GPIO/PWM1/UART1 TX pad、自时基、SPI/I2C 空载 | 固定跳线回环、I2C/SPI 目标器件、仪器波形、多板 |
| 安全启动 | 未实现 | CRC32 损坏检测、A/B 回退 | 签名、密钥、调试锁定、反回滚和安全生产 |

## 2. 本次自动化检查

### SDK、规格与 Boot ROM

```powershell
.\scripts\generate-sdk.ps1 -Check
cmake --build .\build\sdk
python -m unittest discover -s tools\tests -p 'test_*.py' -v
```

结果：生成头与规范一致；SDK 全量构建完成，所有 `.omcu` 镜像使用硬件 ABI `0x00000009`；
Boot ROM fixture 检查通过；Python 测试 **12/12** 通过。

### RTL、CPU、外设与产品顶层

```powershell
$tests = 'timer','gpio','uart','spi','i2c','wdt','pwm','irqctrl','sysctrl', `
  'wdt-supervisor','timer1','alarm','pulse','fault','alarm-pulse-fabric', `
  'fault-fabric','timer1-fabric','pwm1','pwm1-fabric','uart1','pinmux', `
  'user-flash','pcpi-div','system','system-uart','sdk-isa','sdk-peripherals', `
  'sdk-i2c','sdk-irq','tn9k-wdt','tn9k-peripherals','tn9k-pwm1', `
  'tn9k-timer1','tn9k-boot-request','mcu-top','tn9k'
$tests | ForEach-Object { .\scripts\run-rtl-smoke.ps1 -Test $_ }
```

结果：**36/36** 通过，重点包括：

- RV32IM 的乘、除、取余及标准边界；旧 `rv32imc` 二进制不属于产品 ABI；
- GPIO 两级同步、兼容全端口稳定滤波、按针 2/4/8 样本独立滤波、普通/FAULT 快照；ALARM0、PULSE0、FAULT0 和增强 WDT；
- UART/SPI/I2C、GPIO、定时器、PWM、IRQCTRL、FAULT0 等配置/命令寄存器的部分 MMIO 写拒绝；
- Bootloader 请求、复位原因、运行 tick、User Flash 模型、A/B 路径，以及编译固件到 Tang 顶层 pad 的数字路径。

Icarus Verilog 会对部分 `always_comb` 常量选择和 `unique case` 输出已知的信息性限制提示；它们不等于 RTL 失败，也不构成“零警告仿真签核”。应保留日志并用 HIL/其他工具复核。

## 3. ABI 0.9 最终产品 P&R / packing

运行：

```powershell
$tools = (Resolve-Path .\.venv\yowasp-gowin\Scripts).Path
.\scripts\build-tangnano9k-open.ps1 -McuMode `
  -ToolBin $tools `
  -BuildDirectory .\build\tangnano9k-mcu-release-drain
```

manifest：`build/tangnano9k-mcu-release-drain/omcu_tn9k_mcu_manifest.json`。

| 项目 | 记录值 |
| --- | --- |
| 顶层 / 器件 | `omcu_tn9k_mcu_top` / `GW1NR-LV9QN88PC6/I5`（GW1N-9C） |
| 产品模式 | `mcu_mode=true`；Bootloader 固化在 FPGA 配置中，客户应用写入独立 User Flash A/B 槽 |
| Boot ROM / SRAM | 4 KiB（1,024 words） / 44 KiB（45,056 B） |
| User Flash | 77,824 B（76 KiB），2 × 36,864 B 槽，单应用载荷上限 36,800 B |
| Boot ROM 哈希链 | SDK 输入 SHA-256 `533429919b5ac3d040d4fb8d48fcc1a1e6b5f9f54ee39c3e074321d8a4951983`；综合/P&R BSRAM 初始化指纹一致 `e3d5e52effc71700d47918be95a0c72b1578c0d6cc709cd88b2f87d95b712f42`（2 个单元） |
| `.fs` SHA-256 | `3c2b9943bc93bcb42f52006d8cf4b34e0a3ffb310b7bfc9b2aaa278386099` |
| 时钟 | `platform.clk_27m_i`：27.000 MHz 约束，51.318897 MHz 实现，17.551038 ns 裕量 |
| LUT4 / DFF / BSRAM | 7,188 / 8,640（83.19%）；2,620 / 6,480（40.43%）；24 / 26（92.31%） |
| ALU / MULT36X36 / IOB | 1,310 / 6,480；1 / 5；15 / 276 |
| 工具 | YoWASP Yosys 0.68、nextpnr-himbaechel-gowin 0.11.1、Apycula 0.32 |

该结果证明这一源码、约束、Boot ROM 和目标器件可以完成开源综合、P&R 与 packing；它**不**证明该文件已经下载到真实板，也不证明引脚、电平、Flash 或外设行为。

Yosys 会对顶层 I2C/GPIO 三态 Pad 发出有限三态支持警告；P&R/packing 成功不能描述为“零警告签核”。

### 3.1 DFF 5k 探索的否决记录

为验证“将 DFF 利用率拉到 5k”是否仍能作为产品功能交付，完整 ABI 0.9 顶层曾加入一个 12-bit GPIO
流式记录器。200 / 184 / 128 / 64 / 32 样本候选的综合资源分别为
7,521 / 5,207、7,484 / 5,015、7,497 / 4,343、7,509 / 3,575、7,523 / 3,191（LUT4 / DFF）；
所有候选均未通过精确目标器件的布局布线，128 样本还额外尝试了 placer-heap-beta=1.00 与不同 seed。

这是一项失败的资源实验，不是 ABI 或发布工件：未生成可发布 .fs、未改变 SDK/寄存器，也不应用于 HIL。
结论是当前约束下可 P&R 的发布基线是第 3 节记录的 7,188 LUT4 / 2,620 DFF / 24 BSRAM，而非“5k DFF”
的名义目标。详细推导见[资源扩展路线图](resource-expansion-roadmap.md)。

## 4. 实体板 HIL：已完成与剩余门禁

当前一块板已完成：SRAM/配置 Flash 下载 CRC、配置固化后空白恢复、User Flash A→B→A、回读 CRC、
原子提交、BOOT ACK；`omcu_mcu_selftest` 又完成 24/24，并以真实 WDT 复位验证
`RESET_CAUSE=0x2`、`RESET_COUNT=1`。独立模板应用在仓库外编译得到 656 B 载荷，烧录后实板持续输出
`my_omcu_app is running`。原始自检日志和固定回环步骤见[外设实体板验收](mcu-peripheral-qualification.md)。

剩余门禁：

1. 先 SRAM 下载 `.fs`，检查 27 MHz、LED、UART0 和外部复位；核对 manifest 后再固化配置 Flash，至少做 10 次冷启动。
2. 空白/有效/损坏的 A/B 镜像、正常升级、重复帧/重连，以及擦除、数据页写入、`END` 校验、最终提交四阶段断电。
3. GPIO 电平/高阻、RGB LCD 共线、UART0/1、PWM0/1 波形、TIMER1 编码器/噪声、GPIO 共享和独立滤波（掩码、2/4/8 样本）及快照。
4. ALARM0、PULSE0、FAULT0 门控/清除、WDT 预警/窗口/heartbeat/真实复位时序；故障试验只连接安全逻辑负载和人工受控条件。
5. I2C 上拉、ACK/NACK/时钟拉伸；SPI 回环、TF 互斥及 DS3231、AT24Cxx、TMP102、MCP3008、MCP4921、W5500 目标模块与链路。
6. 温度、电压、长线、反复擦写和外部电源矩阵；按实际板卡 revision、模块和本次 `.fs` SHA-256 记录完整日志。

## 5. 对外发布卫生与安全缺口

```powershell
git status --short
git diff --check
git ls-files | Select-String -Pattern '(?i)(\.fs$|\.bit$|\.elf$|\.vcd$)'
```

构建位流、私钥、token、`.env`、客户网络信息或受限 IP 不应混入源代码提交。若发布二进制，应将 `.fs`、manifest、报告和哈希作为 GitHub Release 附件保存。远端 CI、实板记录和签核流程仍须独立完成。

当前 CRC32、A/B 与原子提交只解决传输/存储损坏和回退，不提供来源认证。攻击者可接触的产品在量产前必须补充签名验签、信任根/密钥管理、调试锁定、反回滚、威胁建模、安全评审和受控密钥注入流程。在这些条件满足之前，本工程定位为教学、原型与受控环境的 FPGA MCU 平台。
