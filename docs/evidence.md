# OpenMCU-TN9K 的项目边界与证据

Tang Nano 9K 生态中已经存在有价值的 RISC-V 工作，但目前可见项目解决的是不同问题切片：

| 既有工作 | 已证明的内容 | OpenMCU 仍需提供的内容 |
| --- | --- | --- |
| Sipeed <code>picotiny</code> 示例 | PicoRV32、Flash XIP、UART ISP 与显示集成可工作 | 稳定 ABI、SDK、测试矩阵与清晰的产品边界 |
| Sipeed NEORV32 示例 | User Flash 程序存储、GPIO、JTAG、UART 上传可工作 | 可移植 SoC 契约与第三方发布流程 |
| 社区 PicoRV32 项目 | 小型裸机软件与单个外设可工作 | 版本化 API、调试/烧录工具、回归与板卡支持策略 |
| 社区 Ibex + LiteX 项目 | 开源流程下 Ibex + UART + 存储器 + Wishbone 可启动 | 稳健的时序/RAM/波特率验证与受支持发布配置 |
| Tang 专用应用项目 | 复杂的单应用流水线可运行 | 可复用 MCU，而非应用专用协处理器 |

于 2026-08-24 查阅的公开来源：

- <a href="https://github.com/sipeed/TangNano-9K-example">Sipeed TangNano-9K-example</a>
- <a href="https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/examples/neorv32.html">Sipeed NEORV32 示例</a>
- <a href="https://github.com/grughuhler/picorv32_tang_nano_unified">picorv32_tang_nano_unified</a>
- <a href="https://github.com/riscv-ottawa/ibex-tang-nano-oss-cad">ibex-tang-nano-oss-cad</a>
- <a href="https://github.com/LoveLonelyTime/LLTRISC-V">LLTRISC-V</a>
- <a href="https://github.com/calint/tang-nano-9k--riscv--cache-psram">tang-nano-9k--riscv--cache-psram</a>

这是一份生态观察，而非声称不存在其他实现。OpenMCU 的差异化来自一套完整且公开的产品契约：仿真、Tang 后端、SDK、文档、可复现测试门禁和 ASIC 分支在同一持续维护的项目中协同演进。

## 板级绑定的来源可追溯性

对 OpenMCU Tang Nano 9K 目标，27 MHz 时钟、复位、LED、UART 与扩展引脚的起始约束，已依据公开 Sipeed <code>picotiny</code> 项目和公开板卡资料独立交叉核对。最初的 LED 来源核对使用提交 <code>c3b795799f23de91982be52db4273a8eea100cdb</code>（仅从上列第一个来源克隆检查）。OpenMCU 顶层 RTL 与约束均为独立编写；没有复制上游 RTL、IP 核或生成的工程文件。

这只建立了起始约束集的可追溯性，不是实体板验证。Tang Nano 9K 测试仍必须确认实际板卡修订、USB 上电、复位极性、LED 极性、时钟稳定性、I/O Bank 电压、SPI/TF 卡冲突、I2C 上拉和时序报告。具体约束与安全检查表见 <a href="zh-CN/hardware-and-pins.md">硬件与引脚</a>。
