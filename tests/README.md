# OpenMCU 验证与测试计划

“能够综合”不是“可交付 MCU”。每个外设和每条固件更新链都应经过从最小 RTL 到实板的分层验证，且报告中必须标明证据级别。

```mermaid
flowchart LR
  A[单元 RTL] --> B[CPU / MMIO 集成仿真]
  B --> C[编译后的 SDK 固件仿真]
  C --> D[镜像与串口协议单元测试]
  D --> E[FPGA 综合 / P&R / 位流 manifest]
  E --> F[实体 Tang 板 HIL]
  F --> G[电源循环、掉电、寿命和发布签核]
```

## 自动化 RTL 冒烟测试

安装 Icarus Verilog，或设置 `OMCU_IVERILOG_BIN` 指向其 `bin` 目录。从仓库根目录运行：

```powershell
.\scripts\run-rtl-smoke.ps1 -Test gpio
.\scripts\run-rtl-smoke.ps1 -Test timer
.\scripts\run-rtl-smoke.ps1 -Test uart
.\scripts\run-rtl-smoke.ps1 -Test spi
.\scripts\run-rtl-smoke.ps1 -Test i2c
.\scripts\run-rtl-smoke.ps1 -Test wdt
.\scripts\run-rtl-smoke.ps1 -Test pwm
.\scripts\run-rtl-smoke.ps1 -Test sysctrl
.\scripts\run-rtl-smoke.ps1 -Test user-flash
.\scripts\run-rtl-smoke.ps1 -Test system
.\scripts\run-rtl-smoke.ps1 -Test system-uart
.\scripts\run-rtl-smoke.ps1 -Test tn9k-wdt
.\scripts\run-rtl-smoke.ps1 -Test tn9k
.\scripts\run-rtl-smoke.ps1 -Test mcu-top
```

- `user-flash`：对齐、读、页擦除、字写入、错误状态和忙信号的行为模型检查。
- `system`：小型 RV32I 程序经过 PicoRV32、真实 MMIO 和 GPIO 的首个 CPU/总线/外设集成门。
- `system-uart`：经 CPU/MMIO 配置 UART0 后验证真实串行字节。
- `tn9k-wdt` / `tn9k`：经过 Tang 顶层的复位释放、看门狗和低有效 LED 逻辑检查；不等同于实际 Gowin 板。
- `mcu-top`：使用仅仿真的 `FLASH608K` 端口桩件编译产品顶层，运行已提交 Boot ROM 的空 User Flash 扫描，检查产品封装确实走向物理 Flash 分支；它不模拟真实 Gowin 擦写行为。

每个可公开外设还应覆盖：复位值、字节写掩码、保留位、读写副作用、中断时序、随机/边界值以及编译后 SDK 集成。

## SDK、镜像与协议测试

先构建 SDK，再运行编译固件相关用例：

```powershell
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
.\scripts\run-rtl-smoke.ps1 -Test sdk-isa
.\scripts\run-rtl-smoke.ps1 -Test sdk-peripherals
.\scripts\run-rtl-smoke.ps1 -Test sdk-i2c

python -m unittest `
  tools.tests.test_omcu_bootloader_fixture `
  tools.tests.test_omcu_image `
  tools.tests.test_omcu_flash_protocol -v
```

- `sdk-isa`：编译器到硬件的 RV32IMC、启动数据重定位、压缩指令和乘除法通路。
- `sdk-peripherals`：特性发现、SPI0、WDT0、PWM0 和 GPIO 成功码。
- `sdk-i2c`：开漏目标夹具、地址、写/读字节、最终 NACK 和 STOP。
- `test_omcu_image`：`.omcu` 头部、固定 ABI/地址、长度、对齐、CRC 和破坏检测。
- `test_omcu_flash_protocol`：帧编码、CRC、长度限制和重传相关协议不变量。
- `test_omcu_bootloader_fixture`：SDK 刚生成的 Boot ROM 与产品 FPGA 顶层默认固化的 Boot ROM 逐字比较；允许注释和换行不同，但不允许指令内容漂移。

这些测试不直接替代“启动器在真实 User Flash 上写入并重新启动应用”的端到端板级测试。

## FPGA 构建与下载验证

产品模式需要额外检查工程完整性和位流构建：

```powershell
.\scripts\check-tangnano9k-project.ps1 -McuMode
.\scripts\build-tangnano9k-open.ps1 -McuMode `
  -ToolBin C:\toolchains\yowasp-gowin\Scripts `
  -BuildDirectory .\build\tangnano9k-mcu
```

审阅输出中的顶层名称、`mcu_mode`、User Flash 几何、时序、资源、Boot ROM 初始化指纹和 `omcu_tn9k_mcu_manifest.json` 的 SHA-256。P&R 成功只能证明该次工具运行的网表/约束结果；还不能证明板卡连接、下载、复位或持久存储行为。

## 必做实板 HIL 矩阵

在对外宣称“可用 MCU”前，至少记录以下每项的板号、位流哈希、应用镜像哈希、工具版本、串口日志和结果：

| 项目 | 最低通过标准 |
| --- | --- |
| FPGA 首次固化 | SRAM 试运行通过后，配置 Flash 下载、冷启动和 manifest 哈希一致。 |
| 空白设备恢复 | 无有效应用时，启动器持续监听并可通过 UART 写入首个 `.omcu`。 |
| 正常升级 | 有旧应用时按复位进入窗口，完成 A/B 切换并运行新应用。 |
| 断电恢复 | 擦除、DATA、END 前和最终提交后分别断电；提交前保持旧槽可启动。 |
| 串口异常 | 丢包、重复帧、错误 CRC、错误长度、错误 ABI 均被安全拒绝或幂等处理。 |
| 外设与引脚 | UART、LED、GPIO、I2C、SPI/TF 冲突、PWM、WDT 在真实电平和外设上通过。 |
| 重复升级 | 覆盖预期的擦写/更新次数，记录失败、回退与恢复结果。 |

只有这些 HIL 项目、供电/温度边界和产品安全策略完成后，才可把平台从工程预览提升为客户可交付版本。
