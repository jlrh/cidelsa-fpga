# Bloques 2 + 3 — VRAM + Fetch + Color (pipeline de vídeo)

**RTL:** `rtl/vis_vram.v`, `rtl/vis_palette.v`, `rtl/vis_video.v` ·
**Harness:** `sim/verilator/tb_video_replay.cpp` ·
**Estado:** ✅ VALIDADO **sim == golden == MAME 0.00%** (0/86436 px, escena `tabla`, 2026-06-29)

## Bloque 2 — VRAM (`vis_vram.v`)
PAGE RAM 1K×8, CHAR RAM 2K×8, PCB RAM 2K×1. Puerto de lectura de vídeo (asíncrono en esta versión
sim==golden) + puerto de escritura de CPU (síncrono, para el bloque 6). Con `define REPLAY` precarga
las 3 memorias desde `debug/destryer/dumps/*.hex` (volcado de MAME).

## Bloque 3 — Fetch + Color (`vis_video.v` + `vis_palette.v`)
`vis_video` integra timing (bloque 0) + vram + paleta y, por cada píxel visible, reproduce
`screen_update` del CDP1869 (traducción EXACTA del golden):
- Celda: `cell_x = (hcount-54)/width`, `cell_y = (vcount-44)/height`; rejilla `cols×rows`.
- `page_addr = hma + cell_y*cols + cell_x` (wrap en `pmemsize`) → `pmd` (code).
- `column = page_addr[10] ? 0xff : pmd`; `char_addr = (column<<3)|(cma&7)` → `char_data`.
- patrón 6px = `char_data[5-px6]`; `ccb0=bit6`, `ccb1=bit7`; `pcb` de PCB RAM.
- `get_pen(ccb0,ccb1,pcb,col,cfc,bkg)` → pen; píxel OFF o fuera de rejilla → `bkg`.
- `vis_palette`: pen(0..71) → RGB (pesos 30/59/11).

Config de display (const en frame) entra por puertos (la pone `vis_regs` o el harness con la
config verificada de la escena).

## Versión combinacional (sim==golden) vs síntesis
Esta versión usa **lectura asíncrona** de las RAM + div/mod por píxel para casar EXACTO con el golden
(sin offset de pipeline). Para **síntesis MiSTer** habrá que: (1) BRAM registrada (puertos `jtframe`-
style / M10K) con prefetch de celda, (2) sustituir div/mod por contadores de celda, (3) calibrar el
offset de pipeline contra este mismo golden. Eso es fase posterior (bloque 4/síntesis).

## 🐞 Bug cazado (lección Verilog): literal estrecho
`wire [5:0] rows = 6'd216 / height;` → **`6'd216` se trunca a 6 bits = 24** (no 216) → `rows=24/8=3`
en vez de 27 → sólo se pintaban 3 filas de caracteres (síntoma: "media pantalla sin pintar"). Fix:
`9'd216`. **Lección: los literales en expresiones aritméticas deben tener ancho suficiente para su
valor, no sólo para el resultado.** (También: default en `always@(*)` para evitar latches.)

## Validación
Replay: `vis_vram` precarga los `dumps/`, `tb_video_replay` fija la config verificada, corre 1 frame,
captura los píxeles `de` → `raw/sim_snaps/tabla.ppm`. Comparado con el golden = **0.00%**.
Build:
```
cd sim/verilator
verilator --cc --exe --build -O3 --top-module vis_video -DREPLAY \
  ../../rtl/vis_video_timing.v ../../rtl/vis_vram.v ../../rtl/vis_palette.v ../../rtl/vis_video.v \
  tb_video_replay.cpp -o vis_video_replay && ./obj_replay/vis_video_replay
```
Artefactos: `debug/destryer/compare/tabla_3way_mame_gold_sim.png`, `sim_tabla_rotada.png`.
</content>
