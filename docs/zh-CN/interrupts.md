# OpenMCU v0.4 中断开发约定

OpenMCU v0.4 为 RV32IMC FPGA 目标提供了一条真正可执行的外部中断链路：外设事件捕获、
软件使能和应答寄存器、CPU 投递、固定向量、完整 C ABI 现场保护，以及 SDK 分发入口。
凡是 `SYSCTRL.FEATURES` 声明 `OMCU_FEATURE_IRQCTRL` 的仿真或 Tang Nano 9K 封装，
都遵循这一约定。

## 先明确边界

这里实现的是 **PicoRV32 自定义中断 ABI**，不是 RISC-V 特权架构。因此它没有
`mtvec`、`mstatus`、`mie`、`mip`、PLIC、CLINT、标准 RISC-V 调试传输，也不支持嵌套
机器中断。可移植 OpenMCU 程序只能调用 `omcu.h` 的 C API；不要自行发射 PicoRV32
自定义指令，也不要依赖 q 寄存器内容。

地址、来源到 CPU bit 的映射属于 ABI 主版本 0 的公开合同。以后只能在新 ABI 次版本中
追加新来源，并同步增加功能位；已经发布的来源不会换 bit。

## 中断如何从外设走到 C 函数

```text
GPIO / UART / TIMER / SPI / I2C / WDT 事件
                    |
                    v
        IRQCTRL：sticky pending + enable + force
                    |
                    v
         PicoRV32 外部输入 bit 8 到 bit 13
                    |
                    v
 固定向量 0x10 -> SDK 包装器 -> omcu_irq_dispatch(mask)
                    |
                    v
                  RETIRQ 返回主程序
```

| CPU bit / SDK 常量 | 来源 | 必须先处理的外设状态 |
| --- | --- | --- |
| 8 / `OMCU_IRQ_GPIO0` | GPIO0 | 处理边沿，然后 W1C `IRQ_STATUS`。 |
| 9 / `OMCU_IRQ_UART0` | UART0 | 在 `RX_VALID` 为一时读取 `DATA`。 |
| 10 / `OMCU_IRQ_TIMER0` | TIMER0 | 按需要停止/重装，再 W1C `STATUS.PENDING`。 |
| 11 / `OMCU_IRQ_SPI0` | SPI0 | 如有需要读取结果，再 W1C `STATUS.DONE`。 |
| 12 / `OMCU_IRQ_I2C0` | I2C0 | 完成本字节事务，再 W1C 终态状态位。 |
| 13 / `OMCU_IRQ_WDT0` | WDT0 | 执行产品级策略，再清除 expiry 或停止/喂狗。 |

PicoRV32 的 bit 0 到 bit 2 保留给它自己的 timer、非法指令与总线错误路径。bit 3 到
bit 7、bit 14 到 bit 31 在本平台被硬件永久屏蔽。`OMCU_IRQ_EXTERNAL_MASK` 精确等于
`0x0000_3F00`。

## IRQCTRL 寄存器

IRQCTRL 基址为 `0x4000_7000`；字段总表见英文
[registers.md](../registers.md)。

| 偏移 | 寄存器 | 作用 |
| --- | --- | --- |
| `0x00` | `PENDING` | 只读；sticky/current 来源，位置就是 CPU bit。 |
| `0x04` | `ENABLE` | 读写；以同样 bit 位置使能每个来源。 |
| `0x08` | `CLEAR` | 只写；写一清 sticky 与软件强制来源。同周期真实来源优先。 |
| `0x0C` | `FORCE` | 只写；写一产生软件中断，适用于诊断。 |
| `0x10` | `ACTIVE` | 只读；`PENDING & ENABLE`，也是送给 CPU 的 mask。 |
| `0x14` | `HIGHEST` | 只读；最小编号的 active CPU bit；没有则为零。 |

`PENDING` 会在来源被禁用时仍保存短脉冲。`ENABLE` 仅影响投递，不影响捕获。
`FORCE` 与真实外设使用完全相同的公开 bit mask，必须通过 `CLEAR` 清除。

## SDK 初始化与用户处理函数

使能前，先清掉旧的外设状态和 IRQCTRL 状态：

```c
#include "omcu.h"

void omcu_irq_dispatch(uint32_t pending) {
  if ((pending & OMCU_IRQ_TIMER0) != 0u) {
    OMCU_TIMER0->ctrl = 0u;                         /* 停止或按产品需求重装 */
    OMCU_TIMER0->status = OMCU_TIMER_STATUS_PENDING; /* 先清来源 */
    omcu_irqctrl_ack(OMCU_IRQ_TIMER0);              /* 再清 IRQCTRL */
  }
}

static void enable_timer_irq(void) {
  omcu_irqctrl_set_enable(0u);
  omcu_irqctrl_ack(OMCU_IRQ_EXTERNAL_MASK);
  omcu_timer_start_periodic(0u, 27000u);
  omcu_irqctrl_set_enable(OMCU_IRQ_TIMER0);
  (void)omcu_irq_global_enable();
}
```

`omcu_irq_dispatch()` 是 SDK 中的 weak 函数。应用定义一个同名的 strong 函数后即可
覆盖它；参数 `pending` 带有所有同时 active 的 CPU bit。应用必须处理自己使能的全部
bit，或者在返回前禁用并确认不处理的来源。固定安全顺序是：

1. 消费、清除、禁止或重装产生事件的外设状态。
2. 用 `omcu_irqctrl_ack()` 向 `IRQCTRL.CLEAR` 写对应 bit。
3. 从 C 函数返回；包装器恢复被打断的程序。

如果外设仍保持高电平来源而先清 IRQCTRL，硬件会再次把它写回 sticky pending。这是有意
设计，用来防止丢中断；因此必须遵循“先外设、后 IRQCTRL”的顺序。

`omcu_irq_global_enable()`、`omcu_irq_global_disable()` 与
`omcu_irq_restore()` 操作 CPU 的自定义 IRQ mask。前两个函数会返回旧 mask，临界区应
保存并恢复旧值，而不是假定此前一定处于全局开启状态。

## 向量、现场与限制

复位从 `0x0000_0000` 开始；链接脚本保留 `0x00` 到 `0x0F` 的四条非压缩复位向量指令。
PicoRV32 在外部中断时跳到 `0x0000_0010`。SDK 包装器会：

1. 通过 PicoRV32 文档定义的 q2/q3 临时寄存器先保护被打断的 `ra`/`sp`；
2. 保存 x1 到 x31 到 128-byte 专用 frame；
3. 切换到 512-byte 专用 IRQ stack；
4. 读取 PicoRV32 q1，作为 `pending` 调用 C 分发函数；
5. 恢复完整整数寄存器现场并执行 `RETIRQ`。

中断活动期间 PicoRV32 不会再次进入中断。处理函数应短小、不要在其中进行无上界的总线
等待，耗时工作应回到主循环完成。q0 到 q3 与自定义指令均由 SDK 包装器管理，应用只使用
公开 C API。

## 可执行回归与硬件边界

`omcu_irq_smoke` 是真实编译出的 C 程序：它配置 TIMER0、使能 IRQCTRL bit 10，并用
strong C 函数处理事件。`omcu_irq_sdk_tb` 将这份 ROM 放进真实 PicoRV32/MMIO RTL，要求
处理函数实际运行、`RETIRQ` 实际回到主程序、且没有 trap 或非法 MMIO。`omcu_irq_ctrl_tb`
还单独验证 sticky、屏蔽、优先级、软件 force 和 clear 语义。

这些是数字 RTL/固件仿真证据。Tang Nano 9K 的真实下载以及 UART/SPI/I2C/GPIO 等电气
回归仍是独立发布门槛，不能用仿真替代。
