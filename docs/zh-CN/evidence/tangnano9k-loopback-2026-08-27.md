# Tang Nano 9K MCU / 六线回环实板记录（2026-08-27）

本记录对应一块通过 USB-C 连接 macOS 的 Sipeed Tang Nano 9K。板卡未插 TF 卡和 RGB LCD，
按[MCU 外设实体板验收](../mcu-peripheral-qualification.md)连接六根无源跳线：

| 跳线 | FPGA pad | 测试路径 |
| --- | --- | --- |
| `L2 → L4` | `37 → 39` | SPI0 MOSI → MISO |
| `L18 → L19` | `53 → 54` | UART1 TX → RX |
| `L12 → L16` | `34 → 42` | GPIO4 / PWM1 CH0 → TIMER1 A |
| `L13 → L17` | `40 → 51` | GPIO5 / PWM1 CH1 → TIMER1 B |
| `L14 → L11` | `35 → 33` | GPIO6 / PWM1 CH2 → FAULT0 |
| `L5 → L8` | `25 → 28` | PWM0 → PULSE0 input 0 |

这六根线只构成外设回环夹具，**不包含 UART0**。产品 UART0 使用 FPGA package pad 17/18，
Tang Nano 9K PCB 已把它们接到板载 BL702 的 USB-UART；同一 USB-C 同时提供下载器和串口，
本板在 macOS 枚举为 `/dev/cu.usbserial-11300` / `11301`，测试使用后者、115200 8N1，
不需要再从排针外接 UART0。

## 1. 最终可追溯工件

| 工件 | 记录值 |
| --- | --- |
| FPGA `.fs` | SHA-256 `cdb0217f7c8a4caf03869aa6f9b08e957ea5b1c89b4289d43b783878f7152056` |
| 构建目录 | `build/tangnano9k-mcu-release-v11-final/`；heap placer beta `0.99`，seed `4` |
| Boot ROM 输入 | SHA-256 `41383f7271935bbbab46bac79df7a0c8c7c8b073428a637336cd2d4f6bf45df1`；代码 3,541 B，BSS 76 B |
| Boot ROM 嵌入 | 综合/P&R 两个 BSRAM 指纹一致：`c0f98c9f20762bd902b3b61ccefba6af5901722c4057878f44d9f574611029ee` |
| 时序 | 27.000 MHz 约束；43.049637 MHz 实现；13.808037 ns 裕量 |
| 资源 | LUT4 7,211/8,640；DFF 2,631/6,480；BSRAM 24/26；ALU 1,316/6,480 |
| 回环应用 | SHA-256 `95e3a8e2c41cb4e3fbce4fb27184bd78b4707109f010c70605f8a976a1b80dde`；3,808 B 载荷；CRC32 `0xa5403be7` |
| 外部模板应用 | SHA-256 `7acccf502b0e74ef530b2c81ecdd1ebe79deee11fd441c11ff1252160506b3f4`；656 B 载荷；CRC32 `0x4acb2894` |

正式 `.fs` 通过仓库下载脚本写入配置 Flash；openFPGALoader 报告擦除、写入 100% 和
`CRC check: Success`。该操作实测会清空 User Flash，因此其后重新执行了应用 A/B 更新。

## 2. 最终 A/B 更新与应用链路

同一最终 bitstream 完成以下两组正常路径：

1. 已有 A 槽回环应用（序号 1）时，将 656 B 外部模板写到 B 槽（序号 2），完成擦除、逐字回读、
   载荷 CRC、状态字单次提交；随后从 B 再把 3,808 B 回环应用写回 A（序号 3）。
2. 最终 `.fs` 固化并清空应用区后，从空白状态写 A 槽 3,808 B，再在同一 Bootloader 会话中
   写 B 槽 656 B；两次均回读 CRC 并原子提交，最后启动 B 槽模板。

模板由仓库外工程形态引用 `sdk/cmake/OpenMCUSDK.cmake` 干净编译，构建器校验 ABI、头部和 CRC。
启动后的 UART0 原始输出为：

```text
my_omcu_app is running
my_omcu_app is running
```

最终固化后的 A/B 更新日志 SHA-256 分别为
`c93a76989317f049c5b54a982000d0b859e6cfb19d787469d46f55ca6df1ed34` 和
`5f9f048d8af8b310bdb796d2c165330a20a0fc66aba6d5673d629335261aa575`；模板运行日志为
`73335505b8c0c05ce0a56d5b6f985b1504d64bb9b03bdab2a00ff5f5220d8c4c`。

## 3. 六线回环结果

从 A 槽序号 3 启动后得到：

```text
OMCU_LOOPBACK_SELFTEST V1 BEGIN
PASS HARDWARE_CAPABILITIES
PASS HARNESS_GPIO
PASS UART1_LOOPBACK
PASS SPI0_LOOPBACK
PASS TIMER1_ENCODER_LOOPBACK
PASS PWM1_TIMER1_LOOPBACK
PASS PWM0_PULSE0_LOOPBACK
PASS FAULT0_GPIO_GATE_LOOPBACK
RESULT PASS pass=8 fail=0
```

结论：最终 `.fs` 哈希、当前单板、应用和六线夹具下，八项数字闭环 **8/8 通过**。转录日志
SHA-256 为 `60e5262a528f1ee112d6f3da360fc75e2a8e0e15e53fc17fb1b9101500dbd752`。

首轮镜像曾得到 7/8，只有 `TIMER1_ENCODER_LOOPBACK` 失败。根因是测试固件分别清除/设置两个
编码器输出，让真实引脚出现额外中间 Gray 状态；修正为计算新值后对 `GPIO.OUT` 做一次 32-bit
原子写入。相同两根线已在 GPIO 和 PWM1/TIMER1 回环中独立通过，修正后稳定得到上述 8/8。

## 4. `BEGIN` 超时的定位与关闭

旧版在已有有效应用时可返回 HELLO，但紧随其后的 `BEGIN` 无 ACK。旧槽始终保持可启动，事务未进入
DATA/END；这证明回退有效，但当时不能算升级通过。分阶段 UART 诊断最终确认：

- `HELLO` 已经扫描 A/B、计算当前应用 CRC 并发送响应；
- 主循环在**发送响应以后**又无条件重复完整 Flash 目录扫描；
- 主机按停等协议收到 HELLO 后立即发送 75 B 的 BEGIN，而 UART0 只有单字节 RX 寄存器；重复扫描期间
  无法取走字节，发生 overrun，BEGIN 整帧丢失。

最终 Bootloader 只在响应前完成必要扫描并更新缓存；发送 HELLO/ACK 后立即回到收帧循环。END 与
BOOT 同样先更新缓存、再响应，避免下一帧被耗时 Flash 访问阻塞。修复后 A→B→A 与固化后的
空白→A→B 均实板通过。

诊断还发现擦除后 ERASE 下降到 NVSTR 下降之间原先只等“下一个 256-clock 边界”，最短可能只有
一个时钟，违反 Gowin UG295 的 `Tnvh ≥ 5 µs`。最终状态机增加对齐态和完整 256-clock 等待，
在 27 MHz 下保持至少 9.48 µs；RTL 回归新增不少于 256 周期的断言。页面 18（B 槽首地址）和
页面 36 的独立 FLASH608K 擦/写/擦探针均返回 `UFLASH RESULT 0`，进一步排除了地址或宏单元故障。

## 5. 证据边界

本次证明特定单板上的配置固化、板载 UART0、正常 A/B 更新、应用构建/启动和六线数字回环。
它不覆盖 I2C 目标 ACK/读写、ADC/DAC/W5500 等外置模块、示波器/逻辑分析仪波形精度、最大速率、
长线/负载、电压/温度、ESD/EMC、多板一致性、反复冷启动、擦写寿命、各阶段断电或量产资格。
