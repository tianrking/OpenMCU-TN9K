# ARM backend reservation (no ARM IP included)

This directory intentionally contains no ARM/Cortex-M RTL, netlist or generated
IP. A synthesizable ARM CPU is not a generic dependency that can be fetched and
republished without an applicable Arm license, delivery package and explicit
redistribution rights.

The `vendor/arm-designstart/` and `vendor/arm-ip/` directories are ignored by
Git for that reason. An authorized integrator may use this repository's public
peripheral and board contracts, but must create an independent ARM target with
its own CPU/bus bridge, startup code, linker script, validation suite and
licensing record. It must not replace or silently alter the RV32IMC target.

Read the complete Chinese integration gate before beginning:
[`docs/zh-CN/arm-license-and-integration.md`](../docs/zh-CN/arm-license-and-integration.md).

Until an authorized, reproducible ARM build has passed the same simulation,
P&R, board-programming and public-redistribution checks as the RISC-V target,
this directory is a boundary marker—not an ARM MCU release.
