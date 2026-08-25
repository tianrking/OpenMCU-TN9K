# OpenMCU v0 架构约定

## 产品边界

OpenMCU 是一个小型、常规、便于软件开发的 RISC-V MCU。它不是 FPGA 演示协议、可运行 Linux 的计算机，也不是自定义 ISA 实验。

首个 CPU 适配器必须实现符合标准的 32 位 RISC-V 裸机目标。Tang Nano 9K 的可执行产品适配器采用紧凑的 PicoRV32；较长期的 SystemVerilog 产品路线可评估 Ibex 适配器。无论 CPU 内核如何替换，都必须放在 CPU 适配层之后，且不得改变公开外设 ABI。

## 稳定的 v0 内存映射

| 地址范围 | 模块 | 说明 |
| --- | --- | --- |
| <code>0x0000_0000–0x0000_FFFF</code> | Boot ROM 窗口 | 不可变复位向量和产品启动器 |
| <code>0x1000_0000–0x1000_FFFF</code> | 主 SRAM 窗口 | 平台封装选择 FPGA BRAM 或 ASIC SRAM 宏 |
| <code>0x2000_0000–0x20FF_FFFF</code> | User Flash 窗口 | Tang Nano 9K 产品模式使用 76 KiB GW1NR User Flash；旧 QSPI 宏仅为别名，不是 XIP |
| <code>0x4000_0000–0x4000_0FFF</code> | GPIO0 | v0 可移植 GPIO 外设 |
| <code>0x4000_1000–0x4000_1FFF</code> | UART0 | 控制台、下载器与诊断 |
| <code>0x4000_2000–0x4000_2FFF</code> | TIMER0 | v0 可移植定时器 |
| <code>0x4000_3000–0x4000_3FFF</code> | SPI0 | 外部设备 / QSPI 控制边界 |
| <code>0x4000_4000–0x4000_4FFF</code> | I2C0 | 标准传感器总线 |
| <code>0x4000_5000–0x4000_5FFF</code> | WDT0 | 独立看门狗 |
| <code>0x4000_6000–0x4000_6FFF</code> | PWM0 | 边沿对齐 PWM 发生器 |
| <code>0x4000_7000–0x4000_7FFF</code> | IRQCTRL | 外部事件锁存、屏蔽、软件触发与优先级视图 |
| <code>0x4000_8000–0x4000_8FFF</code> | UART1 | 无大 FIFO 的可复用第二串口 |
| <code>0x4000_9000–0x4000_9FFF</code> | TIMER1 | 16-bit 捕获、滤波与正交编码器 |
| <code>0x4000_A000–0x4000_AFFF</code> | PWM1 | 四路共享相位、16-bit PWM |
| <code>0x4000_B000–0x4000_BFFF</code> | PINMUX | UART1/PWM1/TIMER1 的显式 pad 所有权 |
| <code>0x4000_F000–0x4000_FFFF</code> | SYSCTRL | 芯片 ID、ABI、特性位、构建 ID、实际 ROM/SRAM KiB |

兼容发布不得移动既有模块。新增能力必须使用新的地址范围；不兼容行为必须对应新的主设备版本。

表中 ROM 和 SRAM 区域是保留地址窗口，并不承诺每个平台都实现 64 KiB。Tang Nano 9K 产品封装默认使用 8 KiB Boot ROM 与 44 KiB SRAM；这是经开源 P&R 流验证的全 BSRAM 配置（26/26 BSRAM）。可移植系统仍为其他平台保留参数化能力，SYSCTRL 在第三方固件依赖前公开精确可用容量与特性位图。

## 可移植 MMIO 事务

第一代内部总线有意保持简洁。CPU 适配器将原生总线转换为以下信号：

~~~text
req, write, address[31:0], write_data[31:0], write_strobe[3:0]
                                -> ready, read_data[31:0], error
~~~

这避免将 PicoRV32、Ibex、LiteX、Wishbone、APB、Gowin 或 ASIC 的实现细节暴露给外设。v0 外设总线为单主设备；简单模块可单周期就绪。未来的互连可以流水化事务，但必须保持可见的访问顺序和寄存器语义。

## v0 可执行 CPU 适配器

<code>rtl/cpu/omcu_picorv32_system.sv</code> 将可移植模块组成一个可执行的 RV32IMC 系统。它把 PicoRV32 置于内存映射适配器之后，并连接：

~~~text
PicoRV32 -> ROM / SRAM / OpenMCU MMIO fabric
                                      -> GPIO0 + UART0/1 + TIMER0/1 + SPI0 + I2C0 + WDT0 + PWM0/1
                                      -> PINMUX + SYSCTRL diagnostics
                                      -> IRQCTRL -> PicoRV32 IRQ 位 8..15
~~~

该适配器启用已批准的 <code>M</code>、<code>C</code> 指令扩展。快速乘法器和紧凑 32 步 PCPI 除法器保留标准 RV32M 语义；为给完整 P1 外设腾出资源，寄存器堆为单端口、移位器为迭代实现。它刻意不承诺 <code>Zicsr</code>、特权机器态、标准 RISC-V Trap CSR、PLIC/CLINT、调试支持、原子操作或浮点；PicoRV32 内部 <code>cycle/instret</code> 也不属于公开 ABI，软件使用 SYSCTRL 64-bit tick。

它实现了单独版本化的 PicoRV32 自定义 IRQ ABI：IRQCTRL 将八个外设源映射到 CPU 位 8 至 15，SDK 独占固定 <code>0x10</code> 向量并完整保存 C ABI 上下文。精确的非标准边界与确认顺序见 <a href="interrupts.md">中断约定</a>。非法事务或写 ROM 事务会被应答并作为仿真/bring-up 诊断呈现；这个最小适配器暂不把它们转换为 RISC-V 访问异常。

ROM 初始化文件只是仿真/FPGA bring-up 机制，不是客户更新方案。Tang Nano 9K 产品启动路径为：

~~~text
不可变启动器 -> 已验证的 GW1NR User Flash A/B 应用镜像 -> SRAM 执行
~~~

客户应用不会被编译进 FPGA 配置。

## 复位与时钟约定

- <code>clk_i</code> 是经过平台专用 PLL/时钟封装后的同步系统时钟；通用 RTL 不得实例化 Gowin PLL。
- <code>rst_ni</code> 为低有效复位，由平台异步置位，只能在时钟锁定有效后同步释放。
- 所有公开外设寄存器均复位为已文档化的值。
- ASIC A0 使用外部时钟输入与外部复位监控器；内部 RC 振荡器、欠压检测和低功耗时钟属于后续版本。

## 硬件/软件版本握手

已实现的 v0 SYSCTRL 模块公开 <code>OMCU</code> 芯片标识、ABI 主/次版本、特性位图、构建标识、实际 ROM/SRAM KiB、复位原因、64-bit 运行 tick、内部复位计数和受控的 Bootloader 请求。固件必须拒绝 ABI 主版本不受支持的设备，不能意外写入不兼容寄存器。详见 <a href="registers.md">寄存器参考</a>。

## 平台拆分

~~~text
             共用 RTL 与寄存器规范

   | CPU 适配器 -> MMIO Fabric -> 可移植外设 |

       仿真封装         Tang Nano 封装          ASIC 封装

      RAM 模型       Gowin RAM/PLL/I/O      SRAM/Pad/DFT/时钟
~~~

FPGA 开发板是 ASIC 功能的硬件模型，并不表示时钟、SRAM、Flash、I/O 时序、供电或复位电路等同于最终芯片。在启动 MPW/代工厂实现之前，必须通过 <a href="../asic/README.md">ASIC 交接边界</a> 的交付门禁。
