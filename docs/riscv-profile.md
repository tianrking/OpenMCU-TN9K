# OpenMCU-TN9K RISC-V v1 配置

## 固定的编译器目标

Tang Nano 9K v1 硬件与 SDK 固定使用 **<code>rv32imc</code> 与 <code>ilp32</code> ABI**。这是一个有意保持紧凑的 MCU 级、已批准的非特权 RISC-V ISA 配置；它不表示实现了所有 RISC-V 扩展。

| 组成 | OpenMCU-TN9K v1 的承诺 |
| --- | --- |
| 基础整数 ISA | RV32I，32 个通用 32 位寄存器 |
| 乘除法 | <code>M</code>，由 PicoRV32 的快速乘法与除法 PCPI 单元实现 |
| 代码密度 | <code>C</code>，在取指和译码路径中启用 |
| 编译器 ABI | <code>ilp32</code>、小端、无操作系统裸机环境 |
| 同步 | CPU 适配器接受 <code>FENCE</code>；v1 总线仅有一个主设备，MMIO 保持顺序 |
| 构建参数 | <code>-march=rv32imc -mabi=ilp32</code> |

<code>RV32IMC</code> 是规范的 RISC-V ISA 命名。实现来源是 <a href="../LICENSES.md">LICENSES.md</a> 中固定的 PicoRV32 修订版；其上游文档说明该内核可配置为 RV32IMC。

## 明确不包含的能力

第三方代码在 v1 中不得假定具备以下任一能力：

- <code>A</code>、<code>F</code>、<code>D</code>、<code>Q</code>、<code>B</code>、向量、Hypervisor、Supervisor 或 User-mode ISA；
- 通用 <code>Zicsr</code> CSR 读写、机器态异常 CSR、PMP 或标准 RISC-V 调试传输；
- 标准 RISC-V 中断控制器、PLIC/CLINT、特权中断 CSR，或应用直接使用 PicoRV32 自定义 IRQ 指令码；
- 非对齐访问、缓存一致性、DMA 或 Linux 支持。

CPU 可以通过 PicoRV32 支持的计数器编码读取内部周期/指令计数器，但这不构成完整 <code>Zicsr</code> 扩展承诺。ABI 0.5 通过 <code>omcu.h</code> 提供了一条刻意收窄、已经文档化的 PicoRV32 自定义 IRQ 路径：六个外部源使用位 8 至 13，SDK 独占 <code>0x10</code> 向量，应用提供 C 语言分发钩子。这不会使内核成为特权 RISC-V 实现。

今后若接入标准完整的异常/中断内核适配器，属于新的硬件能力，必须同步更新 SYSCTRL 特性位和 SDK 支持。具体的非标准边界见 <a href="interrupts.md">中断约定</a>。

## 为什么它是 9K 的默认配置

9K FPGA 应服务于产品级微控制器外形：完整 32 寄存器 ABI、紧凑代码、硬件乘除法和桶形移位器。浮点、原子操作和向量会占用宝贵的 LUT/BRAM，却不是常见 GPIO、传感器、显示和控制固件的刚需。

最终资源与时序边界必须以实际构建和布局布线报告为准，不能以文字估算代替。
