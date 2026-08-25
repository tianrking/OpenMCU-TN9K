# 验证门禁与证据

本文记录 OpenMCU-TN9K 的验证层级、自动化证据和仍未完成的实体板门禁。它不是“已量产”声明；源码、仿真、构建、P&R、实板和 ASIC 流片的证据不能互相替代。完整中文产品状态见 <a href="zh-CN/datasheet.md">工程数据手册</a> 与 <a href="zh-CN/validation-and-release.md">验证与发布状态</a>。

## Tang Nano 9K 发布前的必过门禁

1. 每个外设和寄存器副作用均有 RTL 单元测试。
2. SoC 仿真覆盖复位、Trap、中断、GPIO、UART 回环、SPI 和 I2C 事务夹具。
3. 使用固定版本交叉编译器构建 RISC-V 固件。
4. Gowin 综合和布局布线必须没有未约束时钟，并保留时序报告。
5. 实板测试必须覆盖冷复位、1,000 次复位循环、标称波特率 UART、Flash 更新中断、GPIO 回环、定时器/PWM 测量以及 I2C/SPI 回环。
6. 发布物必须可复现：位流哈希、固件哈希、工具版本和板卡修订均需记录。

## 声称 ASIC 前的必过门禁

FPGA 验证是必要条件，但远远不够。ASIC 发布还需要选定 PDK 流程、Pad Ring、ESD 与供电检查、SRAM 宏集成、DFT/扫描计划、时序签核、DRC/LVS、封装选择、晶圆/封装芯片 bring-up，以及 ATE 或量产测试策略。

## 本工作区的验证环境

2026-08-25 时，该工作区的全局 <code>PATH</code> 提供 Git、CMake、Ninja，但不直接提供 Verilog 仿真器、Yosys、Gowin EDA、openFPGALoader 或 RISC-V 交叉编译器。以下检查使用了工作区本地 Icarus Verilog 11.0、工作区本地 xPack GNU RISC-V Embedded GCC 15.2.0-1，以及隔离的 YoWASP 环境。

xPack Windows 压缩包 SHA-256 与 <a href="../toolchains/riscv-none-elf-gcc-15.2.0-1.lock.json">固定锁文件</a> 中的值一致；开源 FPGA 包版本记录在 <a href="../toolchains/yowasp-gowin.lock.json">YoWASP 锁文件</a>。

## 已通过的定向 RTL 与固件仿真

以下自动化检查已通过：

- <code>omcu_timer_tb</code>：定时器基础行为；
- <code>omcu_gpio_tb</code>：GPIO 基础行为；
- <code>omcu_uart_tb</code>：8-N-1 TX、RX 数据恢复、状态和 RX 中断行为；
- <code>omcu_spi_tb</code>：8 位 mode-0 传输、MISO 采样、自动片选、DONE IRQ 与 W1C 完成状态；
- <code>omcu_i2c_tb</code>：开漏 START/STOP/重复 START、MSB 优先读写、ACK/NACK 状态、命令序列错误、<code>BUS_ACTIVE</code>、DONE IRQ 与目标时钟拉伸等待；
- <code>omcu_wdt_tb</code>：喂狗、到期、IRQ、复位请求与 W1C 到期状态；
- <code>omcu_pwm_tb</code>：占空窗口、周期回绕和反相；
- <code>omcu_irq_ctrl_tb</code>：屏蔽时锁存、固定 GPIO/UART/TIMER/SPI/I2C/WDT CPU 位映射、使能/清除顺序、软件触发和最低编号优先级；
- <code>omcu_mmio_fabric</code>：已实现可移植外设的编译集成；
- <code>omcu_sysctrl_tb</code>：ABI、特性、构建和存储器元数据编码；
- <code>omcu_picorv32_system_tb</code>：五条指令 RV32I ROM 通过 PicoRV32 执行，并观察到 GPIO0 输出使能/高电平；
- <code>omcu_picorv32_uart_system_tb</code>：RV32I 镜像通过真实 MMIO Fabric 配置 UART0 并发出已检查串口字节；
- <code>omcu_tn9k_bringup_top_tb</code>：围绕同一可执行系统增加 27 MHz 复位释放和低有效 LED 映射；
- <code>omcu_rv32imc_sdk_tb</code>：xPack GCC 以 <code>-march=rv32imc -mabi=ilp32</code> 构建 SDK，GNU objcopy 生成 ROM 镜像，并通过真实 PicoRV32、启动 <code>.data</code> 复制、MMIO Fabric 与 GPIO 外设执行；反汇编包含压缩指令及 <code>mul</code>、<code>div</code>、<code>divu</code>、<code>rem</code>、<code>remu</code>；
- <code>omcu_peripheral_sdk_tb</code>：已编译 C SDK 调用发现必需特性、配置 PWM0/WDT0、执行真实 SPI0 单字节传输，并通过 GPIO 报告成功且没有产生看门狗复位请求；
- <code>omcu_i2c_sdk_tb</code>：已编译 C SDK 经真实 PicoRV32/MMIO/I2C 路径，对开漏目标夹具执行地址/写/读字节序列，采样目标响应并发送最后一字节 NACK；
- <code>omcu_irq_sdk_tb</code>：已编译 <code>omcu_irq_smoke</code> 通过 IRQCTRL 使能 TIMER0，进入真实 <code>0x10</code> PicoRV32 自定义 IRQ 向量，调用强 C 分发钩子，确认来源，并以 <code>RETIRQ</code> 返回主循环，期间无 Trap 或非法 MMIO；
- <code>omcu_tn9k_wdt_reset_tb</code>：已编译 C 固件有意使 WDT0 到期，Tang 复位释放封装将 SoC 复位并重新启动；
- <code>omcu_tn9k_peripheral_io_tb</code>：已编译 SDK 固件到达实际 Tang 顶层 SPI0 片选、PWM0 和三态 GPIO/I2C Pad 适配器；这是数字顶层连通性测试，不是连接器电气测试；
- <code>omcu_user_flash_tb</code> 与 <code>omcu_tn9k_mcu_top_tb</code>：User Flash 控制器与产品模式顶层回归；
- <code>scripts/generate-sdk.ps1 -Check</code>：生成的 C 寄存器定义与 <code>spec/omcu-v0.json</code> 一致；
- <code>tools.tests.test_omcu_bootloader_fixture</code>、<code>tools.tests.test_omcu_image</code>、<code>tools.tests.test_omcu_flash_protocol</code>：Boot ROM 固件夹具、独立镜像格式和 UART 下载协议共 9 项 Python 测试通过。

Icarus 对 <code>unique case</code> 以及 <code>always_comb</code> 中常量选择灵敏度会给出信息性限制提示；没有报告编译失败。这些提示不能被描述为正式仿真器签核。

## 开源“源码到位流”检查

针对精确 Tang Nano 9K 目标，以下检查已经通过：

- <code>scripts/check-tangnano9k-project.ps1 -McuMode</code>：GOWIN 工程覆盖全部规范 RTL 源、Tang 封装和 MCU Pad 绑定；
- <code>scripts/build-sdk.ps1</code>：在固定 GNU 工具链下构建 SDK、启动器和独立应用镜像；
- <code>scripts/build-tangnano9k-open.ps1 -McuMode</code>：产品模式通过 Yosys 0.68、nextpnr-himbaechel-gowin 0.11.1 与 Apycula 0.32 完成综合、P&R 和打包；
- <code>scripts/program-tangnano9k.ps1 -Destination sram -WhatIf</code>：在不访问硬件的前提下，验证产物清单、位流哈希、目标检查和下载命令构造。

每次位流构建会把输入 <code>.hex</code> 转为 2,048 字、NOP 填充的稠密镜像，在前端解析时作为 Boot ROM 的字面 <code>$readmemh</code> 输入，并对四个 Boot ROM BSRAM 单元的 <code>INIT_RAM_xx</code> 数据在综合 JSON 与 P&R JSON 中计算哈希。两份指纹不一致时构建失败。因此哈希链证明编译的固件确实进入初始化 BSRAM 和最终打包 FPGA 镜像，强于仅记录预期输入文件名。

当前产品模式 <code>omcu_tn9k_mcu_top</code> 的记录位于 <code>build/tangnano9k-mcu-verify/</code>：时钟约束 27.000 MHz，实际 40.189697 MHz，裕量 12.155038 ns；LUT4 为 6,594/8,640（76.32%），DFF 为 1,758/6,480，BSRAM 为 26/26。<code>omcu_tn9k_mcu.fs</code> 的 SHA-256 是 <code>1869a8d66a11970a35602d2826a7ef0838a05498467f9d7b9a4216830927b3c2</code>。完整清单见 <a href="open-pnr.md">开源 P&R 指南</a>。

## 历史 bring-up 记录

以下是保留的 ABI 0.4 / pre-v0.4 ROM 选择基线。它们采用相同器件、约束、存储器几何和工具版本，但不使用后来的独立可更新 MCU 产品 RTL，因此不能替代当前产品模式结果。

| 镜像 | 输入 SHA-256 | BSRAM 指纹（综合 = P&R） | 打包位流 SHA-256 |
| --- | --- | --- | --- |
| <code>omcu_irq_smoke</code>（历史 ABI 0.4） | <code>1409af0b9d1a1498520e6378752a2959c7d58979a4d5f0c232fa5bdd253d0b4d</code> | <code>173d1cf6c36fc89aedc62a7e5bff39cb255e064d2bfccaa616ec0bc604295c82</code> | <code>71e660f93b7ff190adfebffc697944b03c5175309f7bb5523a811448de5f5395</code> |
| <code>omcu_tn9k_board_demo</code> | <code>b35a525d571abe90fe034373e8108a4843544e78b59189cdeade8c3fab19bb30</code> | <code>291fd35b7018e0b5b45a3995793ed94b16811bf19569fec304d3238ec7172655</code> | <code>615ac5b62e9a84ab538cb9d831aaef3d668fb43370b569b5f7adfc4590c97e3a</code> |
| <code>omcu_peripheral_smoke</code> | <code>dbaf313dc1b12980e954665b799ea53578a31b1a1ea0d05a34961581c7f6acd7</code> | <code>4b1ecd0e29b6ae5ebfe9548d76193cf1ea17207f64a290e57b23b1c4acc3e86f</code> | <code>2f33fc5518a8fdedb1520aa185a115c68babf27421d7d6368fcb68b53f5f31e8</code> |

历史结果的最终路由报告为单一 <code>system.clk_i</code> 域：27.000 MHz 约束下达到 45.554 MHz（计算裕量 15.085 ns），资源为 5,892/8,640 LUT4（68.19%）、1,643/6,480 DFF（25.35%）、26/26 BSRAM、1,056/6,480 ALU（16.30%）、5 个 MULT36X36 中的 1 个，以及 276 个 I/O buffer 中的 15 个（包含双向 Pad buffer）。
Yosys 对 I2C 和 GPIO 顶层 Pad 适配器发出已知的受限三态支持警告；日志被保留，结果不得描述为零警告签核。脚本仅在 nextpnr 正常完成、BSRAM 初始化比对通过且满足时序阈值后退出成功。开源 P&R 结果仍不是实体板测试，也不是与厂商流程等价的声明。

## 仍未完成的门禁

上述检查建立了定向 RTL 行为、编译器/仿真器集成和可复现 FPGA 配置镜像。烧录器真实连通和实体板行为仍未验证：目前没有证据表明该 <code>.fs</code> 已加载到此开发板，复位、时钟、LED 极性、UART 电气行为和连接器 I/O 均需要真实板矩阵。

仓库含 GitHub Actions 工作流，可安装 Icarus 和 GNU RISC-V 工具链、运行 smoke suite 并构建所有当前 SDK 固件目标；另有基于 xPack 的主机矩阵在 Windows/macOS 构建全部 SDK 镜像，Linux SDK 任务覆盖 POSIX 入口和已编译固件 RTL 仿真。工作流配置本身不是 CI 已通过的证据；必须在 GitHub Actions 中查看对应提交的实际结果。
