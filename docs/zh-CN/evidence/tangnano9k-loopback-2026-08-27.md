# Tang Nano 9K 六线回环实板记录（2026-08-27）

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

## 可追溯工件

- FPGA `.fs` SHA-256：`3c2b9943bc93bcb8cb42f52006d8cf4b34e0a3ffb310b7bfc9b2aaa278386099`
- 修正后回环 `.omcu` SHA-256：`95e3a8e2c41cb4e3fbce4fb27184bd78b4707109f010c70605f8a976a1b80dde`
- `.omcu`：格式 v2，硬件 ABI `0x00000009`，3808 B 载荷，载荷 CRC32 `0xa5403be7`
- 串口：`/dev/cu.usbserial-11301`，115200/8N1
- 原始成功转录 SHA-256：`f6c74fadcb10c632b3d56d8853c150daceb3f0d89c9f0a57274a9d7ded91db3f`

## 执行与结果

主机先监听串口，再把上述产品 `.fs` 临时加载到 FPGA SRAM，使 Bootloader 进入发现窗口。
Bootloader 识别当前应用为槽 B、序号 4，将修正后的镜像写入非活动槽，完成 User Flash 回读 CRC、
原子提交和切槽。目标输出为：

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

结论：当前单板、当前位流、当前应用与六线夹具下，八项数字闭环 **8/8 通过**。

## 首轮 7/8 与修正

首轮镜像 SHA-256
`43b6a7e32e8ed9ae39e9b840dad3afde0feccd16e094ac82f7e86ab78efac2f4` 得到 7/8；只有
`TIMER1_ENCODER_LOOPBACK` 失败。同一 `L12/L13 → L16/L17` 两根线已在 `HARNESS_GPIO` 和
`PWM1_TIMER1_LOOPBACK` 中通过，因此不是缺线或孔位错误。

根因是测试固件先清除两个编码器输出，再分别置位 A/B。真实引脚会看到这些中间状态，Timer1
正确地把它们计为额外 Gray 跳变。修正为读取 GPIO 输出锁存、计算两个相位的新值并对 `GPIO.OUT`
执行一次完整 32-bit 写入；交叉编译、镜像校验、`timer1` 与 `tn9k-timer1` RTL 回归通过后，实板
得到上述 8/8。

## 更新异常与保护复核

测试后尝试把 656 B 的普通模板应用写回非活动槽时，主机在 `BEGIN` 后超过 180 秒没有收到 ACK；
事务在 `DATA` 和 `END` 之前终止，因此没有提交目标槽。重新加载 FPGA SRAM、且不发送任何更新命令后，
Bootloader 仍从原有效槽启动，目标再次输出同一份 8/8 转录。这证明本次异常没有破坏当前有效应用，
但不等于异常根因已关闭。

当前板上最新应用仍是回环自检（槽 A、序号 5）。下一步应在完全断电冷启动后复现模板恢复，并记录
Bootloader BEGIN 分阶段诊断；在此之前，不把这一轮结果描述为“所有更新故障注入已通过”。

## 证据边界

这次回环不覆盖 I2C 目标 ACK/读写、ADC/DAC/W5500 等外置模块、示波器/逻辑分析仪的波形精度、
最大速率、长线/负载、电压/温度、ESD/EMC、多板一致性、擦写寿命或量产资格。
