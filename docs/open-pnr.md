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
For an isolated Windows environment, install those packages into a virtual
environment, then pass its `Scripts` directory to the build script:

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

`RomInitFile` must be an existing file inside the repository. The script applies
it to the Tang top-level `ROM_INIT_FILE` parameter before Yosys elaborates the
design and records the project-relative image path, ROM/SRAM geometry, tool
versions and artifact SHA-256 in the manifest. `-RomKiB` / `-SramKiB` are
available for controlled experiments, but firmware must use a matching linker
script when either changes.

The script keeps its output under `build/tangnano9k-open/`, which must be
inside the repository because the YoWASP WebAssembly executables consume
project-relative paths. It emits:

- `omcu_tn9k_bringup.json` — post-synthesis Gowin JSON netlist;
- `omcu_tn9k_bringup_pnr.json` — placed and routed netlist;
- `omcu_tn9k_bringup_report.json` — clock and resource report;
- `omcu_tn9k_bringup.fs` — packable FPGA configuration image;
- `omcu_tn9k_bringup_manifest.json` — tool versions, artifact paths, SHA-256,
  timing and selected resource counts.

The command fails if synthesis, placement/routing or packing fails; if an
expected artifact is absent; if the report does not contain exactly one clock;
or if the achieved frequency is below its constraint. The generated files are
ignored by Git because they are reproducible build outputs, not source of
truth.

## Recorded result and boundary

The local full-memory run recorded on 2026-08-25 completed the exact target
with the compiled `peripheral_smoke` SDK ROM, 8 KiB ROM and 44 KiB SRAM. Its
report found `system.clk_i` at 37.803 MHz against a 27 MHz constraint
(10.584 ns calculated margin), with 6,167/8,640 LUT4s, 1,606/6,480 DFFs,
26/26 BSRAMs, 1,056/6,480 ALUs, one of five MULT36X36 blocks, and 15/276 I/O
buffers. The generated `.fs` SHA-256 was
`9384549f0f380e26e3b23b2d7d00f3bcf127d556553670e263f30e6ff3f77c83`.
The detailed evidence is in [`docs/validation.md`](validation.md).

Yosys emitted generic warnings from its Gowin BRAM mapping library about
out-of-range byte selects during synthesis. P&R and packing still succeeded;
the warnings are retained in `yosys.log` and must not be described as a
warning-free sign-off.

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
