# Licensing and provenance

Unless a file says otherwise, project-authored RTL, SDK source, build scripts
and documentation in this repository are licensed under
[Apache-2.0](LICENSE). This release decision covers the public OpenMCU-TN9K
source tree only; it does not grant rights to any third-party CPU/IP, Sipeed
board design, GOWIN tooling, FPGA bitstream, or future ASIC mask work.

Generated artifacts are deliberately ignored by Git. A `.fs` created from this
repository is a configuration image for a particular FPGA/toolchain run, not a
separately licensed hardware product. Do not redistribute a generated artifact
without retaining its manifest, build input provenance and relevant tool terms.

The project must never copy a third-party CPU/SoC repository into this tree
without preserving its licence, notices and revision provenance. In particular,
the `vendor/arm-designstart/` and `vendor/arm-ip/` paths are ignored on purpose:
they are reserved for separately obtained, non-redistributable Arm IP and must
not be committed.

## Imported dependency record

The v0 executable simulation/bring-up adapter uses PicoRV32 as a Git
submodule, not a copied source tree:

- upstream: <https://github.com/YosysHQ/picorv32>;
- pinned revision: `a473fc8fca393771d83b0ffcf0b14db3393339d8`;
- path: `third_party/picorv32`;
- licence: ISC, including the upstream copyright notice in
  `third_party/picorv32/COPYING`.

The documentation includes one unmodified Tang Nano 9K Pinmap image from the
Sipeed Wiki repository:

- upstream: <https://github.com/sipeed/sipeed_wiki>;
- upstream path:
  `docs/hardware/zh/tang/Tang-Nano-9K/assets/clip_image010.gif`;
- local path:
  `docs/zh-CN/assets/sipeed-tang-nano-9k-official-pinmap.png`;
- licence: MIT, with the upstream notice retained in
  `docs/zh-CN/assets/LICENSE-Sipeed-Wiki-MIT.txt`.

`docs/zh-CN/assets/openmcu-tn9k-loopback-physical-pinmap.png` is a
project-authored test diagram derived from the published pin numbers,
schematic nets and this repository's constraints.

OpenMCU's own RTL in this initial local foundation has not been granted a
publication licence yet. A release must retain this dependency record and add
the chosen project licence before distribution.
