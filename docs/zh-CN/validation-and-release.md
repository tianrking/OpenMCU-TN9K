# 验证状态与发布门槛

> **当前源代码基线：** ABI `0.6`，P0/P1 已实现
> **当前 FPGA 工件：** `build/tangnano9k-mcu-abi06-final/omcu_tn9k_mcu.fs`
> **结论：** 自动化回归和目标器件 P&R/packing 已通过；实体 Tang Nano 9K HIL 与量产安全门禁尚未完成。

本页明确区分“代码存在”“数字仿真通过”“可生成位流”“实体板通过”和“可量产”。它们不可互相
替代。对外发布时必须同时保存对应 Git commit、`.fs`、manifest、`.omcu`、工具版本与真实板记录。

## 1. 当前证据矩阵

| 层级 | 状态 | 本次证据 | 未覆盖的内容 |
| --- | --- | --- | --- |
| 规格/SDK 同步 | 已通过 | `generate-sdk.ps1 -Check`，ABI 0.6 生成头与 JSON 一致 | 客户项目、第三方工具链兼容性。 |
| SDK / Boot ROM | 已通过 | 全部 SDK 目标编译；`omcu_bootloader.hex` 与 FPGA fixture 逐 word 一致 | 实体 UART 下载与真实 Boot ROM 运行。 |
| RTL / 集成仿真 | 已通过 | 30 个 smoke 目标，含 P0 总线、UART1/PWM1/TIMER1、PCPI div、诊断/Bootloader 与 Tang 顶层 | 真实电平、异步噪声、功率级和 User Flash 行为。 |
| 镜像/下载协议 | 已通过 | 9 个 Python 测试，覆盖 fixture、`.omcu` 完整性、UART 帧/重传不变量 | 真实串口丢包、断电、设备互操作性。 |
| FPGA 产品构建 | 已通过 | 精确目标器件的综合、P&R、packing、ROM BSRAM 指纹和 `.fs` SHA-256 | 下载到实体板、冷启动、电气与长期可靠性。 |
| User Flash A/B | 预 HIL | RTL、Bootloader、镜像与协议已覆盖 | 真正 `FLASH608K` 擦写时序、掉电、寿命、温度。 |
| 安全启动 | 未实现 | CRC32 检测损坏、A/B 回退 | 签名、密钥、调试锁定、反回滚、安全生产。 |

## 2. 本次已运行的自动化检查

### SDK、生成规格和产品工程

```powershell
.\scripts\generate-sdk.ps1 -Check
.\scripts\check-tangnano9k-project.ps1 -McuMode

$prefix = 'C:\...\bin\riscv-none-elf-'
.\scripts\build-sdk.ps1 -RiscvPrefix $prefix
```

结果：产品工程覆盖 20 个规范 RTL 源、25 个 MCU pad 绑定；SDK 全量构建成功，且检查到
`rtl/platform/tangnano9k/firmware/bootloader.hex` 与刚构建的 Boot ROM 完全一致。

### RTL 与固件集成

```powershell
$env:OMCU_IVERILOG_BIN = 'C:\ProgramData\chocolatey\lib\iverilog\tools\bin'

'timer', 'timer1', 'timer1-fabric', 'gpio', 'uart', 'uart1', 'spi', 'i2c', `
  'wdt', 'pwm', 'pwm1', 'pwm1-fabric', 'irqctrl', 'sysctrl', 'pinmux', `
  'user-flash', 'pcpi-div', 'system', 'system-uart', 'sdk-isa', `
  'sdk-peripherals', 'sdk-i2c', 'sdk-irq', 'tn9k-wdt', 'tn9k-peripherals', `
  'tn9k-pwm1', 'tn9k-timer1', 'tn9k-boot-request', 'tn9k', 'mcu-top' |
  ForEach-Object { .\scripts\run-rtl-smoke.ps1 -Test $_ }

python -m unittest `
  tools.tests.test_omcu_bootloader_fixture `
  tools.tests.test_omcu_image `
  tools.tests.test_omcu_flash_protocol -v
```

30/30 RTL/集成 smoke 和 9/9 Python 测试通过。新增的重点覆盖包括：

- PCPI `DIV/DIVU/REM/REMU`、零除和 `INT32_MIN / -1`；
- PWM1/TIMER1 的低 16-bit 寄存器合同与 TIMER1 8-bit 滤波；
- UART1/PWM1/TIMER1 的真实 fabric/pinmux 译码；
- `RESET_CAUSE`、运行 tick、内部复位计数、软件请求一次复位和 Boot ROM 返更新会话；
- 已编译 `rv32imc` 固件经过 PicoRV32/MMIO/Tang 顶层到最终逻辑 pad 的数字路径。

Icarus Verilog 对部分 `always_comb` 常量选择和 `unique case` 报告已知的信息性限制提示。测试仍通过，
但这不是“零警告仿真签核”；发布时应保留日志，并由 HIL/其他工具进一步复核。

## 3. ABI 0.6 最终产品 P&R / packing

运行：

```powershell
$tools = 'C:\...\yowasp-gowin\Scripts'
.\scripts\build-tangnano9k-open.ps1 -McuMode `
  -ToolBin $tools `
  -BuildDirectory .\build\tangnano9k-mcu-abi06-final
```

构建 manifest：
`build/tangnano9k-mcu-abi06-final/omcu_tn9k_mcu_manifest.json`。

| 项目 | 本次记录 |
| --- | --- |
| 顶层 / 器件 | `omcu_tn9k_mcu_top` / `GW1NR-LV9QN88PC6/I5`（GW1N-9C） |
| 构建模式 | `mcu_mode=true`；Bootloader 在 FPGA 配置中，应用独立写入 User Flash A/B。 |
| Boot ROM / SRAM | 8 KiB（2,048 words） / 44 KiB（45,056 B） |
| User Flash | 77,824 B（76 KiB），2 × 36,864 B 槽，单应用载荷上限 36,800 B |
| Boot ROM 哈希链 | SDK 输入 `f04f3ca394ab8de0ae8bca550808d7808649ee093083d9028094e998c8ca5656`；综合/P&R BSRAM 指纹相同 `7cd55876a448ff28dff9e2aa157428a48d1ed64b38a7cac45a810568abb47a28`（4 个单元） |
| `.fs` SHA-256 | `6d7973037b53a33ba1a9f7e113f0ca0ad6acb0b45700ba595ad2842213ccdd9f` |
| 时钟 | `platform.clk_27m_i`：27.000 MHz 约束，40.356754 MHz 实现，12.258037 ns 裕量 |
| LUT4 | 6,844 / 8,640（79.21%） |
| DFF | 2,154 / 6,480（33.24%） |
| BSRAM | 26 / 26（100.00%） |
| ALU / MULT36X36 / IOB | 1,464 / 6,480；1 / 5；15 / 276 |
| 工具 | YoWASP Yosys 0.68，nextpnr-himbaechel-gowin 0.11.1，Apycula 0.32（锁文件见 `toolchains/`） |

该结果证明此精确源码、约束、Boot ROM 和目标器件可以完成开源综合、P&R 与 packing；它**不**证明
同一个文件已经下载到真实板，也不证明任何引脚、电平、Flash 或外设行为。

## 4. 必须完成的实体板 HIL

### 平台固化与基本恢复

1. 先 SRAM 下载本页 `.fs`，检查 27 MHz、LED、UART0 和外部复位。
2. 核对 manifest / SHA-256 后才用 `-Destination flash -ConfirmFlash` 固化配置，至少做 10 次冷启动。
3. 记录板卡 revision、FPGA 丝印、电源、下载器、工具版本、时间和完整日志。

### 用户固件与异常恢复

1. 空白 User Flash、正常 A/B 交替更新、损坏 ABI/CRC/长度、重复帧和重连。
2. 在擦除、数据页写入、`END` 校验、最终提交四阶段分别断电；上电只能启动旧有效槽或等待恢复。
3. 应用调用 `omcu_tn9k_request_bootloader()` 后，确认 `SOFTWARE` 原因、一次复位和持续 UART0 更新会话。
4. 在目标温度/电压下做重复更新和擦写寿命矩阵；以厂商规格和实测记录制定限制。

### P0/P1 外设与电气

1. GPIO 高/低/高阻、RGB LCD 共线互斥、3.3 V Bank 与共地；
2. UART0/1 的 115200 8N1、TX/RX、电平、overrun；
3. PWM0/PWM1 的频率、四路相位、占空比、disable 后低电平，且使用安全逻辑/外部驱动级；
4. TIMER1 的真实 A/B Gray 序列、滤波、正反向、非法跳变和噪声；
5. I2C 上拉、真实 ACK/NACK/时钟拉伸；SPI 回环、TF 互斥和目标设备；
6. DS3231/AT24Cxx/TMP102/MCP3008/MCP4921/W5500 的真实模块与 W5500 链路/IRQ。

## 5. 对外发布卫生

```powershell
git status --short
git diff --check
git ls-files | Select-String -Pattern '(?i)(\.fs$|\.bit$|\.elf$|\.vcd$)'
```

除了有意保留的手写 ROM fixture 外，不提交构建位流、私钥、token、`.env`、客户网络信息或受限 IP。
构建输出本身被 Git 忽略；若发布二进制，建议作为带 manifest/哈希的 GitHub Release 附件，而不是混入
源代码提交。推送后以该 commit 的 GitHub Actions 实际结果作为 CI 证据，本机输出不能替代远端 CI。

## 6. 量产前的安全缺口

当前 CRC32、A/B 和原子提交仅提供传输/存储损坏检测与回退，不提供来源认证。攻击者可接触的
产品在量产前必须加入签名验签、信任根/密钥管理、调试锁定、反回滚、威胁建模、安全评审和受控
密钥注入流程。在这些条件满足之前，工程定位应是教学、原型和受控环境 FPGA MCU 平台。
