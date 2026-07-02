# Cidelsa — MiSTer FPGA

FPGA implementation (MiSTer) of **Cidelsa's "Video System-1"** arcade hardware — an
RCA **CDP1802 (COSMAC)** CPU with **CDP1869/1870** video and **AY-3-8910** sound —
written from scratch in Verilog.

First target: **Destroyer (Cidelsa, 1980)**. The platform family (each a separate core
sharing the common RTL in [`rtl/`](rtl/)) also includes **Altair** and **Draco**.

> ⚠️ **No ROMs here.** This repository contains only HDL and tooling. You must provide
> your own ROMs.

## Status

Work in progress. Video is pixel-perfect against MAME (0.00% on the validated scenes) and
the CPU is validated (OUT stream identical to MAME). Being tested on real MiSTer hardware.

## Layout

| Path | What |
|------|------|
| [`rtl/`](rtl/) | The core: CDP1802 CPU, `vis_*` video, sound, machine wiring (Destroyer/Altair/Draco) |
| [`mister/`](mister/) | MiSTer project — top `Destroyer.sv`, Quartus files, `sys/` framework, `.mra` |
| [`quartus/`](quartus/) | Standalone Quartus project |
| [`sim/`](sim/) | Verilator testbenches |
| [`docs/`](docs/) | Architecture, methodology and per-block notes |
| [`debug/`](debug/) | Comparison tooling + MAME oracle scripts |

## Build

Open the Quartus project in [`mister/`](mister/) (Destroyer revision, DE10-Nano) and compile,
or see [`mister/README.md`](mister/README.md) for details.

## Acknowledgements

- **[Recreativas.org](https://www.recreativas.org/)** — for their work preserving Spanish
  arcade hardware.
- **Ferrán Yago** — creator of the game.
- **The MAME team** — for the emulation used as a golden reference.
- **Claude** — development assistance.

## License

Released under the **GNU General Public License v3.0** — see [`LICENSE`](LICENSE).
