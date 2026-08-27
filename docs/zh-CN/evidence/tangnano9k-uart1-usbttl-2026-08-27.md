# Tang Nano 9K UART1 / USB-TTL 实板记录（2026-08-27）

本记录验证当前 OpenMCU-TN9K ABI 0.9 的 UART1 实物排针路径。测试使用一块 Tang Nano 9K、
板载 USB-C 和一只 FT232R 3.3 V USB-TTL；不更改 FPGA 位流，只通过板载 UART0 更新独立
`.omcu` 应用。

## 1. 接线与主机端口

观察方向为元件面朝上、板载 USB-C 在顶部。完全断电后连接：

| Tang 孔位 | FPGA pin / MCU 功能 | FT232R | 方向 |
| --- | --- | --- | --- |
| `L18` | 53 / GPIO10 / UART1 TX | `RXD` | MCU → USB-TTL |
| `L19` | 54 / GPIO11 / UART1 RX | `TXD` | USB-TTL → MCU |
| `R23` | GND | `GND` | 共地 |

USB-TTL 的 VCC/3V3/5V 均未连接；Tang 由自身 USB-C 供电。测试时未连接 RGB LCD，且原来的
`L18 → L19` 被动回环线已经拆除。

macOS 枚举结果：

| 设备 | VID:PID / 序列号 | 端口 | 用途 |
| --- | --- | --- | --- |
| Tang 板载 BL702 调试器 | `0403:6010` / `FactoryAIOT Pro` | `/dev/cu.usbserial-11301` | UART0 Bootloader 烧录 |
| 外置 FT232R | `0403:6001` / `A50285BI` | `/dev/cu.usbserial-A50285BI` | UART1 实际收发 |

板载 `/dev/cu.usbserial-11300` 是 JTAG 通道，不是 UART1。

## 2. 首轮结果与测试固件根因

首轮使用原始 `omcu_uart1_loopback`：

| 项目 | 值 |
| --- | --- |
| `.omcu` SHA-256 | `4ab68feade6ab8918ac79c1f3265be7f8a0e2d049b7e22b4f6b8be8dffbcd264` |
| 载荷 | 620 B |
| 载荷 CRC32 | `0xc6eb389e` |

停等测试包含测试文字和四轮完整 `0x00..0xFF`，得到 **1054/1054 B**，证明 L19 RX 和 L18 TX
的物理方向、PINMUX、波特率和两个电气路径均能双向工作。但一次连续写入 2,048 B 时只收到
2,017 B，首个错位出现在 offset 124，因此不能把原程序称为可靠连续回显。

根因在应用而非引脚：旧循环读出一个 RX 字节后调用阻塞式 `omcu_uart1_write_byte()`；前一帧仍在
发送时，CPU 等待 TX ready，UART1 的单字节 RX holding register 可能被后续连续字节覆盖并置 overrun。

修正后的 [`sdk/examples/uart1_loopback/main.c`](../../../sdk/examples/uart1_loopback/main.c)使用 256 B
软件环形缓冲，独立轮询 RX 与 TX：只要 RX valid 就立即读走，在 TX ready 时才非阻塞写下一字节。
没有修改 RTL、PINMUX、CST、FPGA `.fs` 或硬件 ABI。

## 3. 修正镜像与烧录

| 项目 | 值 |
| --- | --- |
| FPGA `.fs` SHA-256 | `cdb0217f7c8a4caf03869aa6f9b08e957ea5b1c89b4289d43b783878f7152056` |
| 修正 `.omcu` SHA-256 | `4401c12599637b8a276a5d8cc95e6a6bb94a6d33805d003f1e2b95e3bf4020cd` |
| 文件 / 载荷 | 748 B / 684 B |
| 硬件 ABI | `0x00000009` |
| 载荷 CRC32 | `0xf5bca9e0` |

更新器通过 UART0 识别到当前 B 槽序号 4，将修正镜像写入非活动槽，完成占用页擦除、逐帧写入、
User Flash 回读 CRC、原子提交和 BOOT。该过程只更新 MCU 应用，不重新烧录 FPGA。

## 4. 最终测试结果

新增主机工具 [`tools/omcu_uart_echo_test.py`](../../../tools/omcu_uart_echo_test.py)执行两类测试：

1. 测试文字加四轮 `0x00..0xFF`，每字节停等核对，覆盖所有可能字节值；
2. 32 个连续 2,048 B 数据块，每块改变确定性位图，总计 65,536 B。

原始成功输出：

```text
PASS byte-domain 1048/1048 bytes
PROBE_SHA256 a6d4470aa67b7059548990444934ee1ea5fd86c46f302b2879ad0e518945b5c1
PASS sustained-blocks 32/32
PASS total 65536/65536 bytes elapsed=23.067s
EXPECTED_SHA256 2f70049051634fb2b5be6fadcced7648f3eb4f51eee8ba3fa474ef2d7d0792d8
RECEIVED_SHA256 2f70049051634fb2b5be6fadcced7648f3eb4f51eee8ba3fa474ef2d7d0792d8
RESULT PASS UART_ECHO /dev/cu.usbserial-A50285BI 115200_8N1
```

转录 SHA-256 为
`b6c4467be07a5ffdf8ebe20b3a20df770540bfd38c40663cdea288f5974856ff`。

复现命令：

```sh
python3 tools/omcu_flash.py \
  --port /dev/cu.usbserial-11301 \
  --image build/sdk/omcu_uart1_loopback.omcu

python3 tools/omcu_uart_echo_test.py \
  --port /dev/cu.usbserial-A50285BI \
  --log build/hil/uart1-usbttl.log
```

## 5. 结论与边界

当前单板、当前 FPGA 位流、修正应用、短线 FT232R 和 115200 8N1 条件下，`L19 → UART1 RX →
软件队列 → UART1 TX → L18` 已完成全字节与 64 KiB 无错闭环，两个方向均可作为当前 MCU 的
UART1 使用。

本记录尚不等于最大波特率、长线、不同 USB-TTL、电压阈值、示波器位宽、温度、电磁兼容、多板或
长期无错资格；这些项目仍须按[MCU 外设实体板验收](../mcu-peripheral-qualification.md)继续测试。
