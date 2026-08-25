# OpenMCU 从 FPGA 到 ASIC 的交接边界

此目录定义的是未来 ASIC 的交接条件，不是已经完成的版图、可制造芯片或流片证据。Tang Nano 9K 是当前功能原型目标；只有在 FPGA 上稳定并实测过的合同，才能进入 ASIC 实现。

## 建议的 A0 产品定义

第一颗 OpenMCU 应是务实的外部 QSPI 启动 MCU，而不是假定教育性流程已经提供合格 eFlash、模拟 IP 和量产封装：

- 遵守现有 OpenMCU 内存/MMIO 合同的 RV32I 或受控 CPU 适配器；
- SRAM 宏、不可变 Boot ROM 和外部 QSPI 固件存储；
- GPIO、UART、定时器、SPI/QSPI、看门狗和调试/测试接口；
- 明确的 pad ring、ESD、电源、复位、DFT/scan、封装和 ATE 计划；
- 不默认包含 eFlash、ADC、DAC、USB PHY、无线、PLL、欠压或其他模拟 IP。

FPGA 产品中 User Flash A/B 升级架构是很好的系统软件参考，但 ASIC 的实际非易失存储、启动、加密和寿命必须按选定工艺/IP 重新验证，不能把 Gowin 行为直接等同为硅片行为。

## 可迁移与不可直接迁移的资产

| 可作为单一事实来源 | 必须由 ASIC 重新实现 |
| --- | --- |
| `spec/omcu-v0.json` 与生成的 SDK 寄存器定义 | ROM/SRAM 宏、时钟、复位、pad cell、ESD、DFT |
| `rtl/bus/` 的内存图和总线语义 | 电源域、扫描、物理约束、布局布线和签核 |
| `rtl/peripherals/` 的功能 RTL | 非易失存储控制器、密钥/安全启动、工艺可靠性 |
| `sdk/`、镜像格式和升级状态机 | 封装、ATE、量产测试和生命周期服务 |
| `tests/` 的可复用行为用例 | 角落 STA、DRC/LVS、IR/EM、天线、密度和制造检查 |

`omcu_picorv32_system` 的数组式存储器以及 Tang 顶层不能直接迁移；ASIC 必须换成经表征的宏、合法 pad、时钟/复位、DFT 和技术约束封装。

## 选择 MPW 或代工厂前的门槛

1. 冻结版本化的寄存器参考、启动 ABI、异常/中断策略和外部镜像/升级格式。
2. 在 Tang 实板完成综合、时序、位流哈希、冷复位、外设、应用升级中断和管脚测试。
3. 明确工艺 PDK、标准单元、SRAM、I/O pad、封装和测试策略及其许可/分发范围。
4. 完成带时钟/复位、scan/DFT、pad ring、电源域、ESD 的 ASIC 封装，并进行等价或针对性的 RTL-门级验证。
5. 完成全角落综合/STA、DRC/LVS、IR/EM、天线、ERC、密度/填充和可制造性检查。
6. 在流片前设计晶圆、封装芯片、板卡 bring-up、编程、量产向量和 ATE 覆盖。

| 阶段 | 目的 | 需要的证据 |
| --- | --- | --- |
| FPGA 开发预览 | 固定 ABI，验证数字行为 | RTL/固件/实板矩阵与可重复位流 |
| A0 MPW 学习芯片 | 验证 pad、复位、启动、I/O 和制造假设 | 代工签核报告与封装芯片/板级 bring-up |
| 量产 MCU | 面向第三方长期交付 | 合格工艺/IP、量产测试、供应/安全/升级生命周期策略 |

开源 PDK 流程有助于学习和预硅验证，但不能单独构成可量产 MCU 的供应链或签核证据。
