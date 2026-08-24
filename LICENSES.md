# Licensing decision record

No external release licence is granted by this initial local foundation.

Before publication, the project owner must explicitly choose and document:

1. RTL and SDK licence, likely Apache-2.0 or a compatible alternative;
2. board schematic/PCB licence, likely a CERN Open Hardware Licence variant if
   the hardware is to be open;
3. all imported CPU, debug, memory, boot and tool licences;
4. whether the ASIC implementation files are public, source-available or
   private.

The project must never copy a third-party CPU/SoC repository into this tree
without preserving its licence, notices and revision provenance.

## Imported dependency record

The v0 executable simulation/bring-up adapter uses PicoRV32 as a Git
submodule, not a copied source tree:

- upstream: <https://github.com/YosysHQ/picorv32>;
- pinned revision: `a473fc8fca393771d83b0ffcf0b14db3393339d8`;
- path: `third_party/picorv32`;
- licence: ISC, including the upstream copyright notice in
  `third_party/picorv32/COPYING`.

OpenMCU's own RTL in this initial local foundation has not been granted a
publication licence yet. A release must retain this dependency record and add
the chosen project licence before distribution.
