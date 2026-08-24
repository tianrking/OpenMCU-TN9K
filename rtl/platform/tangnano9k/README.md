# Tang Nano 9K OpenMCU platform backend

`omcu_tn9k_bringup_top.sv` is the executable Tang Nano 9K MCU wrapper for
`GW1NR-LV9QN88PC6/I5` / `GW1N-9C`. It runs the portable RV32IMC SoC at the
board's 27 MHz input, synchronizes reset release, and maps portable peripherals
onto actual top-level pads:

- GPIO0[0:5] -> six active-low on-board LEDs;
- UART0 -> package pads 17/18;
- SPI0 -> pads 38/37/36/39 (shared J5/TF-card signal group);
- I2C0 -> true open-drain pads 26/27;
- PWM0 -> pad 25;
- GPIO0[6:8] -> tri-state expansion pads 28/29/30.

The default 8 KiB ROM + 44 KiB SRAM configuration is intentionally an
all-BSRAM Tang design. The open P&R release flow produces the authoritative
resource report; it has successfully placed and routed this geometry using
26/26 BSRAMs. It is still parameterized for controlled experiments, but a
different memory geometry requires a matching SDK linker script.

## Build a manifest-bound `.fs`

Initialize the separately licensed CPU source, build an SDK ROM image, then
run the pinned open Gowin flow:

```powershell
git submodule update --init --recursive
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-

$tools = 'C:\path\to\yowasp-gowin\Scripts'
.\scripts\build-tangnano9k-open.ps1 -ToolBin $tools `
  -BuildDirectory .\build\tangnano9k-board-demo `
  -RomInitFile .\build\sdk\omcu_tn9k_board_demo.hex
```

The output directory contains a packed `.fs`, its SHA-256 manifest, synthesis
log, P&R log and JSON reports. It also contains the generated dense
`omcu_rom_image.hex`; the manifest hashes both the requested SDK image and this
effective ROM image, then records matching synthesized/P&R BSRAM initialization
fingerprints. The script checks the exact device, all canonical RTL sources,
the CST/SDC constraint set and timing against 27 MHz.

## Download policy

Use the provided hash/manifest-checked script. It defaults to volatile SRAM;
Flash requires an additional deliberate confirmation:

```powershell
.\scripts\program-tangnano9k.ps1 `
  -BitstreamPath .\build\tangnano9k-board-demo\omcu_tn9k_bringup.fs `
  -Destination sram
```

See [`../../../docs/zh-CN/hardware-and-pins.md`](../../../docs/zh-CN/hardware-and-pins.md)
for I/O voltages, I2C pull-ups, the SPI/TF-card conflict and the real-board
release checklist. P&R and top-level simulation verify digital connectivity;
they do not validate this particular board's USB programmer, voltage banks,
connector numbering, LEDs or external-device behavior.
