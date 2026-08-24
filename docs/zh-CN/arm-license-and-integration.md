# ARM 版本：授权边界与独立集成路线

## 结论先行

本公开仓库当前**没有可综合、可烧录、可发布的 ARM/Cortex-M MCU RTL**。这不是遗漏：
Arm Cortex-M 内核 RTL（包括可经 DesignStart/Flexible Access 获得的版本）受单独的
帐户、EULA/IP 许可和交付条件约束。仓库不能复制、上传、反编译或假装拥有它；一个
空壳 Verilog 模块也不能诚实地称为“ARM MCU 已完成”。

RISC-V 版本是可公开构建的完整 FPGA MCU 路线；ARM 版本必须在你已获得明确可用于
Gowin/Tang Nano 9K 的授权、交付物和再分发边界后才进入“可用”状态。

## 为什么不能用 RISC-V 内核换名为 ARM

- ARM 是指令集、异常模型、调试/调试器生态与受许可的 IP 组合，不是一个普通 Verilog
  端口名；
- CMSIS、Cortex-M 的启动代码和软件 ABI 需要与准确的内核、NVIC、SysTick、调试组件
  相匹配；
- 未验证的“ARM compatible”开源/网络 RTL 可能在授权、专利、指令正确性和安全性上都
  不适合作为公共产品；
- 把许可证要求的核心文件推送进公共 GitHub 会违反 IP 许可，也会损害后续商业化。

## 获得授权后的独立实现包

授权所有者应自行接受 Arm 的相应条款，并将交付物放入本机、被 Git 忽略的目录：

```text
vendor/arm-designstart/   # 或 vendor/arm-ip/
```

不要把这些文件、许可证文本、下载 token 或客户资料提交到本仓库。开始集成前要建立一份
**不含受限内容**的接口清单，至少包括：

| 项目 | 必须明确 |
| --- | --- |
| 精确核心 | Cortex-M0/M0+/M1/M23 等、修订号、FPGA 许可范围 |
| 总线 | AHB-Lite / APB 端口、地址相位/数据相位、等待状态和错误响应 |
| 时钟复位 | 27 MHz 或 PLL 频率、reset/lock、低功耗输入 |
| 异常 | 向量表、NVIC 数量、SysTick、HardFault 行为 |
| 调试 | SWD/JTAG 是否可用于 GW1NR-9C，是否需额外 probe/IP |
| 软件 | CMSIS 版本、GCC `-mcpu` / `-mthumb` flags、链接脚本和启动代码 |
| 许可 | 是否允许综合、下载 FPGA、交给第三方使用、公开 wrapper/SDK |

然后应新建**独立**的 `arm/` 目标和 `build/tangnano9k-arm/` 输出，不替换或污染 RISC-V
ABI。可以复用的部分是 GPIO/UART/TIMER/SPI/I2C/WDT/PWM 外设 RTL 与板级 I/O；ARM
总线到 OpenMCU MMIO 的桥、异常/中断、启动代码和软件包则必须专门实现和验证。

## ARM 可宣称完成前必须通过的验证

1. 经授权内核在 GW1NR-LV9QN88PC6/I5 完成综合、P&R、packing，且确实能下载到实体板；
2. CMSIS 启动、向量表、SysTick、NVIC、HardFault、堆栈和链接脚本由 ARM GCC 构建并运行；
3. AHB/APB 桥对所有 OpenMCU 外设进行读、写、byte strobe、错误/等待状态测试；
4. UART、GPIO、PWM、SPI、I2C、WDT 在实体板回归通过；
5. 公开仓库只含你有权公开的 wrapper/SDK/文档，受限 RTL 以私有依赖或合法二进制/IP
   分发方式处理；
6. 发布说明明确 CPU、授权前提、工具版本和哪些文件第三方必须从授权方获得。

在这些条件满足前，正确的产品表述是“ARM 集成预留/待授权”，而不是“ARM 版本完整可用”。
这会保护第三方用户，也会保护本项目的开源和商业路线。
