# 验证状态与发布门槛

> **当前产品基线：** ABI `0.8`、`rv32im` / `ilp32`、4 KiB Boot ROM、44 KiB SRAM、76 KiB User Flash A/B。<br>
> **可追溯 FPGA 构建：** `build/tangnano9k-mcu-abi08-rv32im-release/`。<br>
> **结论：** RTL、SDK、镜像工具和精确目标器件的开源 P&R/packing 已通过；实体 Tang Nano 9K HIL、长期可靠性、安全启动和量产资格尚未完成。

本页明确区分“源码存在”“数字仿真通过”“已生成目标位流”“实体板通过”和“可量产”。它们不能互相替代。对外发布时必须保存对应 Git commit、`.fs`、manifest、`.omcu`、工具版本与真实板记录。

## 1. 证据矩阵

| 层级 | 状态 | 已有证据 | 尚未覆盖 |
| --- | --- | --- | --- |
| 规格 / SDK 同步 | 已通过 | `generate-sdk.ps1 -Check`，ABI 0.8 JSON 与生成头一致 | 客户项目与第三方工具链兼容性 |
| SDK / Boot ROM | 已通过 | 全量 SDK 以 `rv32im` 构建；已提交 Boot ROM fixture 与生成 `.hex` 逐 word 一致 | 实体 UART 下载与真实 ROM 启动 |
| RTL / 集成仿真 | 已通过 | 36 个 smoke 目标，覆盖全部公开外设、CPU、SDK、User Flash 模型、Tang 顶层及新原子 MMIO 合同 | 真实电平、异步噪声、功率级和真实 Flash |
| 镜像 / 下载协议 | 已通过 | Python 单元测试 9/9，覆盖 fixture、镜像完整性与 UART 帧不变量 | 真实串口丢包、断电和设备互操作 |
| FPGA 产品构建 | 已通过（非 HIL） | `GW1NR-LV9QN88PC6/I5` 的综合、P&R、packing、ROM BSRAM 指纹、manifest 和 `.fs` SHA-256 | 下载到实体板、冷启动、电气与长期可靠性 |
| User Flash A/B | 预 HIL | RTL、Bootloader、镜像和协议回退路径 | `FLASH608K` 实际擦写、掉电、寿命、温度 |
| 安全启动 | 未实现 | CRC32 损坏检测、A/B 回退 | 签名、密钥、调试锁定、反回滚和安全生产 |

## 2. 本次自动化检查

### SDK、规格与 Boot ROM

```powershell
.scriptsgenerate-sdk.ps1 -Check
cmake --build .\build\sdk
python -m unittest discover -s tools\tests -p 'test_*.py' -v
```

结果：生成头与规范一致；SDK 全量构建完成，所有 `.omcu` 镜像使用硬件 ABI `0x00000008`；
Boot ROM fixture 检查通过；Python 测试 **9/9** 通过。

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
- GPIO 两级同步、全端口稳定滤波、普通/FAULT 快照；ALARM0、PULSE0、FAULT0 和增强 WDT；
- UART/SPI/I2C、GPIO、定时器、PWM、IRQCTRL、FAULT0 等配置/命令寄存器的部分 MMIO 写拒绝；
- Bootloader 请求、复位原因、运行 tick、User Flash 模型、A/B 路径，以及编译固件到 Tang 顶层 pad 的数字路径。

Icarus Verilog 会对部分 `always_comb` 常量选择和 `unique case` 输出已知的信息性限制提示；它们不等于 RTL 失败，也不构成“零警告仿真签核”。应保留日志并用 HIL/其他工具复核。

## 3. ABI 0.8 最终产品 P&R / packing

运行：

```powershell
$tools = (Resolve-Path .\.venv\yowasp-gowin\Scripts).Path
.\scripts\build-tangnano9k-open.ps1 -McuMode `
  -ToolBin $tools `
  -BuildDirectory .\build\tangnano9k-mcu-abi08-rv32im-release
```

manifest：`build/tangnano9k-mcu-abi08-rv32im-release/omcu_tn9k_mcu_manifest.json`。

| 项目 | 记录值 |
| --- | --- |
| 顶层 / 器件 | `omcu_tn9k_mcu_top` / `GW1NR-LV9QN88PC6/I5`（GW1N-9C） |
| 产品模式 | `mcu_mode=true`；Bootloader 固化在 FPGA 配置中，客户应用写入独立 User Flash A/B 槽 |
| Boot ROM / SRAM | 4 KiB（1,024 words） / 44 KiB（45,056 B） |
| User Flash | 77,824 B（76 KiB），2 × 36,864 B 槽，单应用载荷上限 36,800 B |
| Boot ROM 哈希链 | SDK 输入 SHA-256 `ce3528a1c607e5d6c47c9a75db656c7cf3cb4a230cd6226d701acc06e41de6d2`；综合/P&R BSRAM 初始化指纹一致 `3c1605bcf45d0c27dd0911867b4c9dd8321c2462285f7322f24a418175d36b8d`（2 个单元） |
| `.fs` SHA-256 | `1666a4c6218a040a11b2a21906b7681471ad1ebe847b3c2decf3cd6f4cfeb075` |
| 时钟 | `platform.clk_27m_i`：27.000 MHz 约束，40.533421 MHz 实现，12.366037 ns 裕量 |
| LUT4 / DFF / BSRAM | 6,962 / 8,640（80.58%）；2,511 / 6,480（38.75%）；24 / 26（92.31%） |
| ALU / MULT36X36 / IOB | 1,336 / 6,480；1 / 5；15 / 276 |
| 工具 | YoWASP Yosys 0.68、nextpnr-himbaechel-gowin 0.11.1、Apycula 0.32 |

该结果证明这一源码、约束、Boot ROM 和目标器件可以完成开源综合、P&R 与 packing；它**不**证明该文件已经下载到真实板，也不证明引脚、电平、Flash 或外设行为。

Yosys 会对顶层 I2C/GPIO 三态 Pad 发出有限三态支持警告；P&R/packing 成功不能描述为“零警告签核”。

## 4. 必须完成的实体板 HIL

1. 先 SRAM 下载 `.fs`，检查 27 MHz、LED、UART0 和外部复位；核对 manifest 后再固化配置 Flash，至少做 10 次冷启动。
2. 空白/有效/损坏的 A/B 镜像、正常升级、重复帧/重连，以及擦除、数据页写入、`END` 校验、最终提交四阶段断电。
3. GPIO 电平/高阻、RGB LCD 共线、UART0/1、PWM0/1 波形、TIMER1 编码器/噪声、GPIO 端口滤波和快照。
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
