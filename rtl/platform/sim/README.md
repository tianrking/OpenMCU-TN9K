# 通用仿真平台封装

仿真后端用于在不依赖 Gowin 专有原语的条件下，尽早验证 OpenMCU 的公开功能和 SDK 行为。这里应包含通用同步 ROM/SRAM 模型、GPIO 回环、UART/SPI/I2C 夹具以及需要时的外部存储模型。

所有公共 SDK 示例应先在此类技术无关环境中运行，再进入 Tang Nano 9K 的平台封装和实体板测试。

产品 MCU 模式的 User Flash 行为可以在通用模型中验证协议、状态机、A/B 选择、CRC 和掉电恢复逻辑；Gowin `FLASH608K` 原语、真实擦写时序、电气行为和配置 Flash 仍必须在 Tang 专用流程与实体板上单独验证。仿真通过不等于 FPGA 位流或板级通过。
