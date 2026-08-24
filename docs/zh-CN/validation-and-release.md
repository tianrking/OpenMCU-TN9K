# 验证状态与发布准则

## 当前已经有的证据

本仓库当前提供以下可重复的数字证据：

- 每个 GPIO/UART/TIMER/SPI/I2C/WDT/PWM/SYSCTRL 外设的 RTL 定向测试；
- RV32IMC SDK C 程序由 GNU 工具链构建，再在真实 PicoRV32/MMIO/外设 RTL 内执行；
- Tang 顶层复位、LED 映射、看门狗重启和外设端口穿透测试；
- 精确器件 `GW1NR-LV9QN88PC6/I5` 的开源 Yosys -> nextpnr -> gowin_pack 流；
- 构建 manifest 中的 ROM 输入、内存参数、工具版本、资源、时序和 SHA-256。

执行所有快速回归：

```powershell
$env:OMCU_IVERILOG_BIN = 'C:\toolchains\iverilog\bin'
.\scripts\generate-sdk.ps1 -Check
.\scripts\check-tangnano9k-project.ps1

'gpio','timer','uart','spi','i2c','wdt','pwm','sysctrl','system','system-uart',
'sdk-isa','sdk-peripherals','sdk-i2c','tn9k','tn9k-wdt','tn9k-peripherals' |
  ForEach-Object { .\scripts\run-rtl-smoke.ps1 -Test $_ }
```

Icarus Verilog 会对 `always_comb` 的常量位选与 `unique case` 输出已知的功能限制提示；
这些不是成功证明，也没有被隐藏。所有用来发布的构建仍须审阅实际日志。

## “完成”不等于哪些事情

当前工作区没有已连接的 Tang Nano 9K，也没有 `openFPGALoader`、`gw_sh` 或厂商下载器
可用。因此以下项目都是**未验证**，绝不能写成已通过：

- `.fs` 是否真的写入板载 SRAM/Flash；
- USB 下载器、复位按键、LED、UART 的电气行为；
- 外接 SPI/I2C/PWM/GPIO 的实际电平、时序、总线恢复；
- 任意 GOWIN EDA 版本与开放 P&R 的等价性；
- PSRAM、板载 Flash QSPI-XIP、JTAG、DMA、低功耗、模拟外设、ASIC 后端。

这不是保守措辞，而是可审计产品边界：P&R 成功只证明给定网表、约束与工具组合可以
生成配置文件，不能替代硬件测量。

## 对外发布的门槛

发布可被第三方复现的 RISC-V MCU 版本前，维护者应保存并审阅：

1. 通过的 Git commit、子模块 SHA、`git status` 干净状态；
2. SDK `.hex`、`.fs`、manifest 和 SHA-256；
3. 精确的工具版本及 P&R report（含所有 warning）；
4. 自动化 RTL/SDK 回归和对应 GitHub Actions 的最终 commit CI；
5. 一块或多块真实 Tang Nano 9K 的硬件矩阵，覆盖冷启动、SRAM/Flash 下载、1000 次
   复位、UART、GPIO、PWM、SPI 回环、I2C 目标和异常恢复；
6. 电压/温度/连接器约束以及已知限制的公开说明。

任何一个缺失时，发布说明只能写“RTL/P&R/仿真验证”，不能写“开发板已经完全验证”。

## GitHub 发布卫生

提交或公开推送前运行：

```powershell
git status --short
git diff --check
git ls-files | Select-String -Pattern '(?i)(\.fs$|\.bit$|\.elf$|\.hex$|\.vcd$)'
```

第二个命令应无输出。第三个命令只允许手写的测试 ROM fixture，不应包含生成 bitstream、
私钥、token、`.env`、客户网络信息或受限 Arm IP。推送后比较本地 SHA 与远端分支 SHA，
并只以 GitHub 对该最终 SHA 的 CI 结果作为 CI 通过证据。
