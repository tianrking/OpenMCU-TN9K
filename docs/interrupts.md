# OpenMCU ABI 0.9 中断约定

OpenMCU ABI 0.9 为 RV32IM FPGA 目标保留了一条完整、可执行的外部中断路径。它覆盖外设事件捕获、软件使能与确认寄存器、CPU 投递、固定向量、完整 C ABI 保存/恢复包装器，以及 SDK 分发钩子。该约定适用于声明 <code>OMCU_FEATURE_IRQCTRL</code> 的仿真与 Tang Nano 9K 封装。

## 适用范围与兼容性边界

这是已文档化的 **PicoRV32 自定义 IRQ ABI**，不是 RISC-V 特权架构。特别地，它不提供 <code>mtvec</code>、<code>mstatus</code>、<code>mie</code>、<code>mip</code>、PLIC、CLINT、标准调试传输或嵌套的机器态中断。

可移植 OpenMCU 应用必须使用 <code>omcu.h</code> 中的 C 函数；不得自行发出 PicoRV32 自定义指令码，也不得依赖 q 寄存器内容。

寄存器映射及“来源到 CPU 位”的映射属于 ABI 主版本 0 的一部分。新的来源类型只能通过新的 ABI 次版本和特性位追加。

## 硬件路径与来源映射

~~~text
GPIO / UART0/1 / TIMER0/1 / SPI / I2C / WDT / ALARM0 / PULSE0 / FAULT0 事件
                 |
                 v
          IRQCTRL：锁存 pending + enable + force
                 |
                 v
        PicoRV32 外部输入位 8..18
                 |
                 v
固定向量 0x10 -> SDK 包装器 -> omcu_irq_dispatch(mask)
                 |
                 v
               RETIRQ
~~~

| CPU 位 / SDK 常量 | 来源 | 必须优先处理的外设条件 |
| --- | --- | --- |
| 8 / <code>OMCU_IRQ_GPIO0</code> | GPIO0 | 读取/处理边沿，再对 <code>IRQ_STATUS</code> 执行 W1C。 |
| 9 / <code>OMCU_IRQ_UART0</code> | UART0 | 当 <code>RX_VALID</code> 有效时读取 <code>DATA</code>。 |
| 10 / <code>OMCU_IRQ_TIMER0</code> | TIMER0 | 根据策略停止/重装，再对 <code>STATUS.PENDING</code> 执行 W1C。 |
| 11 / <code>OMCU_IRQ_SPI0</code> | SPI0 | 需要时读取结果，再对 <code>STATUS.DONE</code> 执行 W1C。 |
| 12 / <code>OMCU_IRQ_I2C0</code> | I2C0 | 完成字节操作，再清除终止状态位。 |
| 13 / <code>OMCU_IRQ_WDT0</code> | WDT0 | 执行产品策略，再清除到期状态或停止/喂狗。 |
| 14 / <code>OMCU_IRQ_UART1</code> | UART1 | 当 <code>RX_VALID</code> 有效时读取 <code>DATA</code>。 |
| 15 / <code>OMCU_IRQ_TIMER1</code> | TIMER1 | 先处理 compare/capture/encoder W1C 状态，再确认控制器。 |
| 16 / <code>OMCU_IRQ_ALARM0</code> | ALARM0 | 先 W1C 对应 <code>PENDING</code> bit，再确认控制器。 |
| 17 / <code>OMCU_IRQ_PULSE0</code> | PULSE0 | 读取测量结果，再 W1C <code>STATUS.PENDING</code>。 |
| 18 / <code>OMCU_IRQ_FAULT0</code> | FAULT0 | 先维持外部系统安全并读取强制快照；不得为了清 IRQ 盲目 clear 故障。 |

位 0 至 2 由 PicoRV32 保留给自身的定时器、非法指令和总线错误路径。位 3 至 7 及 19 至 31 在本平台配置中永久屏蔽。<code>OMCU_IRQ_EXTERNAL_MASK</code> 恰为 <code>0x0007_FF00</code>。

## IRQCTRL 寄存器

IRQCTRL 位于 <code>0x4000_7000</code>，字段细节见 <a href="registers.md">寄存器参考</a>。

| 偏移 | 寄存器 | 含义 |
| --- | --- | --- |
| <code>0x00</code> | <code>PENDING</code> | RO：处于 CPU 位位置的锁存/当前来源位。 |
| <code>0x04</code> | <code>ENABLE</code> | RW：相同 CPU 位位置的来源投递使能掩码。 |
| <code>0x08</code> | <code>CLEAR</code> | WO：W1C 清除锁存和软件强制位；仍有效的来源在同时清除时优先。 |
| <code>0x0C</code> | <code>FORCE</code> | WO：W1S 产生软件中断源，适合诊断。 |
| <code>0x10</code> | <code>ACTIVE</code> | RO：<code>PENDING &amp; ENABLE</code>，将被送往 CPU。 |
| <code>0x14</code> | <code>HIGHEST</code> | RO：编号最小的活动 CPU 位；无活动源时为零。 |

<code>PENDING</code> 即使在来源被禁用时也会捕获短外设脉冲。<code>ENABLE</code> 只控制投递，不控制捕获。<code>FORCE</code> 使用与硬件来源相同的公开位掩码，并通过 <code>CLEAR</code> 清除。

## SDK 初始化与处理函数约定

只有清除了陈旧的外设和控制器状态后，才可以使能中断：

~~~c
#include "omcu.h"

void omcu_irq_dispatch(uint32_t pending) {
  if ((pending & OMCU_IRQ_TIMER0) != 0u) {
    OMCU_TIMER0->ctrl = 0u;                         /* 停止或重装策略 */
    OMCU_TIMER0->status = OMCU_TIMER_STATUS_PENDING; /* 先在源端清除 */
    omcu_irqctrl_ack(OMCU_IRQ_TIMER0);              /* 再清除控制器 */
  }
}

static void enable_timer_irq(void) {
  omcu_irqctrl_set_enable(0u);
  omcu_irqctrl_ack(OMCU_IRQ_EXTERNAL_MASK);
  omcu_timer_start_periodic(0u, 27000u);
  omcu_irqctrl_set_enable(OMCU_IRQ_TIMER0);
  (void)omcu_irq_global_enable();
}
~~~

<code>omcu_irq_dispatch()</code> 是 SDK 提供的弱函数。应用应提供一个强定义，它会收到 <code>pending</code> 中所有同时活动的 CPU 位。应用必须服务其启用的所有位，或者在返回前禁用并确认未处理源。安全的确认顺序始终为：

1. 消费、清除、禁用或重装产生条件的外设。
2. 通过 <code>omcu_irqctrl_ack()</code> 向 <code>IRQCTRL.CLEAR</code> 写入对应位。
3. 从 C 钩子返回；包装器恢复被中断的应用。

若电平式来源仍然有效时先清 IRQCTRL，硬件会按设计产生新的锁存事件。这不是丢失中断错误；它明确要求“先外设、后控制器”的顺序。

<code>omcu_irq_global_enable()</code>、<code>omcu_irq_global_disable()</code> 与 <code>omcu_irq_restore()</code> 操作 CPU 已文档化的自定义 IRQ 掩码。使能/禁用函数返回先前掩码；临界区应保存后恢复它，而不能假设此前的全局状态。

## 向量与执行规则

复位从 <code>0x0000_0000</code> 开始；链接脚本将 <code>0x00</code> 至 <code>0x0F</code> 留给四个非压缩复位向量字。PicoRV32 在 <code>0x0000_0010</code> 进入外部中断，SDK 包装器将：

1. 使用 PicoRV32 已文档化的 q2/q3 暂存寄存器保护被中断的 <code>ra</code>/<code>sp</code>；
2. 将 x1 至 x31 保存到专用的 128 字节帧；
3. 切换至专用 512 字节 IRQ 栈；
4. 以 PicoRV32 q1 作为 <code>pending</code> 参数，调用 C 钩子；
5. 恢复完整整数寄存器上下文，并执行 <code>RETIRQ</code>。

PicoRV32 在一个中断活动期间阻止第二次进入。处理函数应保持简短，避免阻塞式总线循环，并把重工作下放到主循环。包装器独占 q0 至 q3 及自定义指令；应用只能使用公开 C API。

## 可执行回归

<code>omcu_irq_smoke</code> 从 C 编译，配置 TIMER0、使能 IRQCTRL 位 10，并使用一个强 C 钩子。<code>omcu_irq_sdk_tb</code> 在真实 PicoRV32/MMIO RTL 中执行该精确 ROM，并要求处理器运行、<code>RETIRQ</code> 返回主循环，且不发生 Trap 或非法 MMIO 事务。<code>omcu_irq_ctrl_tb</code> 另外检查锁存、屏蔽、优先级、软件强制和清除语义。

这些是数字仿真证据；实体 Tang Nano 9K 下载和外设电气验证仍是独立的发布门禁。
