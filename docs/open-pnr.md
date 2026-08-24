# Tang Nano 9K open synthesis, P&R and packing

`scripts/build-tangnano9k-open.ps1` creates an FPGA configuration image from
the portable OpenMCU RTL and the Tang Nano 9K wrapper. It deliberately uses an
open implementation path so that a third party can reproduce the artifact
without an installed GOWIN EDA licence:

```text
SystemVerilog -> Yosys synth_gowin -> nextpnr-himbaechel-gowin -> gowin_pack -> .fs
```

The target is locked to the board's `GW1NR-LV9QN88PC6/I5` package and the
`GW1N-9C` device family. Before synthesis, the script checks that the `.gprj`
file includes every source in `rtl/files.f`, the Tang wrapper, exactly one CST
file and exactly one SDC file. It does not rely on an IDE project silently
omitting a newly added peripheral.

## Reproduce

Initialize the separately licensed CPU source first:

```powershell
git submodule update --init --recursive
```

The package versions used for the recorded result are in
[`toolchains/yowasp-gowin.lock.json`](../toolchains/yowasp-gowin.lock.json).
Use 64-bit Python 3.10 or newer on Windows: the pinned Apycula dependency has
prebuilt `fastcrc` wheels for current Python versions, while Python 3.9 may try
to build that Rust extension locally. For an isolated environment, install the
locked packages into a virtual environment, then pass its `Scripts` directory
to the build script:

```powershell
python -m venv .venv\yowasp-gowin
.\.venv\yowasp-gowin\Scripts\python -m pip install `
  yowasp-yosys==0.68.0.0.post1208 `
  yowasp-nextpnr-himbaechel-gowin==0.11.1.0.post826 `
  apycula==0.32

$tools = (Resolve-Path .\.venv\yowasp-gowin\Scripts).Path
.\scripts\build-tangnano9k-open.ps1 -ToolBin $tools
```

The default uses the minimal LED fixture. The default Tang top-level geometry is
8 KiB ROM plus 44 KiB SRAM; it is intentionally the all-BSRAM configuration.
To build an SDK application into the FPGA boot ROM, first build the SDK and
supply its generated Verilog image. For example, the board demonstration is
selected without editing RTL:

```powershell
cmake -S sdk -B build/sdk -G Ninja `
  -DCMAKE_TOOLCHAIN_FILE=sdk/cmake/riscv32-gcc.cmake `
  -DOMCU_RISCV_PREFIX=riscv-none-elf-
cmake --build build/sdk --target omcu_tn9k_board_demo

.\scripts\build-tangnano9k-open.ps1 -ToolBin $tools `
  -RomInitFile .\build\sdk\omcu_tn9k_board_demo.hex
```

`RomInitFile` must be an existing file inside the repository. The script parses
its `@word-address` records, materializes an exact-size `omcu_rom_image.hex`
with RISC-V NOP fill, and supplies that generated image as a literal
`$readmemh` input while Yosys reads the module that owns the boot ROM. This is
deliberate: changing a string parameter after parsing cannot be treated as
proof that a memory initializer changed. The manifest records the sparse SDK
input hash, the dense effective image hash, and a deterministic fingerprint of
the four boot-ROM BSRAM cells before and after P&R. The build fails if those
two BSRAM fingerprints do not match. `-RomKiB` / `-SramKiB` are available for
controlled experiments, but firmware must use a matching linker script when
either changes.

The script keeps its output under `build/tangnano9k-open/`, which must be
inside the repository because the YoWASP WebAssembly executables consume
project-relative paths. It emits:

- `omcu_tn9k_bringup.json` — post-synthesis Gowin JSON netlist;
- `omcu_tn9k_bringup_pnr.json` — placed and routed netlist;
- `omcu_tn9k_bringup_report.json` — clock and resource report;
- `omcu_tn9k_bringup.fs` — packable FPGA configuration image;
- `omcu_rom_image.hex` — generated dense effective boot-ROM image; and
- `omcu_tn9k_bringup_manifest.json` — tool versions, source/effective ROM
  hashes, pre-/post-P&R BSRAM fingerprints, artifact SHA-256, timing and
  selected resource counts.

The command fails if synthesis, placement/routing or packing fails; if an
expected artifact is absent; if the report does not contain exactly one clock;
or if the achieved frequency is below its constraint. The generated files are
ignored by Git because they are reproducible build outputs, not source of
truth.

## Recorded result and boundary

The current v0.4 source tree was implemented on 2026-08-25 with the compiled
`omcu_irq_smoke` image, 8 KiB ROM and 44 KiB SRAM. Its final report found the
single `system.clk_i` domain at 45.554 MHz against the 27 MHz constraint
(15.085 ns calculated margin), using 5,892/8,640 LUT4s (68.19%),
1,643/6,480 DFFs (25.35%), 26/26 BSRAMs, 1,056/6,480 ALUs, one of five
MULT36X36 blocks, and 15/276 I/O buffers. The manifest verifies that the four
boot-ROM BSRAM initialization fingerprints match before and after P&R.

The two earlier rows below are retained as historical pre-v0.4
ROM-selection evidence. They use the same device, memory geometry and
open-tool flow, but are not a replacement for the current IRQ-enabled result.

| SDK boot ROM | Input ROM SHA-256 | BSRAM initialization fingerprint (synthesis = P&R) | Packed `.fs` SHA-256 |
| --- | --- | --- | --- |
| `omcu_irq_smoke` (current v0.4) | `1409af0b9d1a1498520e6378752a2959c7d58979a4d5f0c232fa5bdd253d0b4d` | `173d1cf6c36fc89aedc62a7e5bff39cb255e064d2bfccaa616ec0bc604295c82` | `71e660f93b7ff190adfebffc697944b03c5175309f7bb5523a811448de5f5395` |
| `omcu_tn9k_board_demo` | `b35a525d571abe90fe034373e8108a4843544e78b59189cdeade8c3fab19bb30` | `291fd35b7018e0b5b45a3995793ed94b16811bf19569fec304d3238ec7172655` | `615ac5b62e9a84ab538cb9d831aaef3d668fb43370b569b5f7adfc4590c97e3a` |
| `omcu_peripheral_smoke` | `dbaf313dc1b12980e954665b799ea53578a31b1a1ea0d05a34961581c7f6acd7` | `4b1ecd0e29b6ae5ebfe9548d76193cf1ea17207f64a290e57b23b1c4acc3e86f` | `2f33fc5518a8fdedb1520aa185a115c68babf27421d7d6368fcb68b53f5f31e8` |

The current v0.4 row is direct evidence that the interrupt SDK firmware reaches
the initialized BSRAMs and final FPGA image. The two historical source-image,
BSRAM-fingerprint and packed-bitstream hash sets are also distinct, which
demonstrates ROM selection rather than merely recording a requested input path.
The detailed evidence is in [`docs/validation.md`](validation.md).

Yosys reported its known limited tri-state support at the top-level I2C and
GPIO pad adapters. P&R and packing still succeeded; the warnings are retained
in `yosys.log` and must not be described as a warning-free sign-off.

This flow demonstrates an implementation-ready `.fs` artifact for the exact
device. It does **not** demonstrate successful board programming, USB power and
reset behavior, LED polarity, UART electrical behavior, or compatibility with
any particular GOWIN EDA release. Those remain explicit physical-board release
gates.

For a safe host-side download, use
[`scripts/program-tangnano9k.ps1`](../scripts/program-tangnano9k.ps1). It
verifies the `.fs` SHA-256 against its manifest and defaults to volatile SRAM.
Persistent Flash programming requires both `-Destination flash` and
`-ConfirmFlash`; a tool exit code is still not a functional-board validation.
