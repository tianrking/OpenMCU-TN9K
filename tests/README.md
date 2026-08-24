# Test plan entry point

Each portable peripheral needs all of the following before it is called part of
the MCU:

1. register reset test;
2. byte-strobe and reserved-bit test;
3. read/write side-effect test;
4. interrupt timing test;
5. randomized or boundary-value test;
6. firmware-level integration test.

The preferred initial stack is a SystemVerilog- or cocotb-based RTL test suite,
then a RISC-V firmware integration test in simulation, then Tang Nano hardware
tests. No board test replaces the first two layers.

## Executable smoke tests

With Icarus Verilog on `PATH`, or with `OMCU_IVERILOG_BIN` set to its `bin`
directory, run from the repository root:

```powershell
.\scripts\run-rtl-smoke.ps1 -Test gpio
.\scripts\run-rtl-smoke.ps1 -Test timer
.\scripts\run-rtl-smoke.ps1 -Test uart
.\scripts\run-rtl-smoke.ps1 -Test sysctrl
.\scripts\run-rtl-smoke.ps1 -Test system
.\scripts\run-rtl-smoke.ps1 -Test system-uart
.\scripts\run-rtl-smoke.ps1 -Test tn9k
```

`system` is intentionally a very small firmware-level test. It loads
`tests/data/gpio_bringup.hex` into the boot-ROM model, executes five RV32I
instructions through PicoRV32, and observes the public GPIO output-enable and
output state. It is the first CPU/bus/peripheral integration gate, not a
replacement for compiled SDK firmware or board testing.

`uart` covers 8-N-1 TX serialization, RX synchronization/data recovery,
sticky error/status behavior and RX interrupt assertion at a small simulation
divider. `sysctrl` checks that the hardware/SDK compatibility metadata is
parameterized correctly.

`system-uart` is a second CPU integration gate: a hand-audited RV32I image
writes UART0 control, divider and data through the real PicoRV32/MMIO path,
then the testbench checks the serialized byte.

`tn9k` adds the 27 MHz reset-release and active-low six-LED board adapter to
the same firmware path. It verifies logic-level behavior only; it does not
validate a Gowin bitstream, timing report, physical pin mapping or a Tang Nano
9K board.
