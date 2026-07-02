# Metodología de validación — Cidelsa (golden-python: MAME → golden → sim → hw)

> Adaptación a Cidelsa del método probado en los cores Gaelco. **Doc canónico de origen:**
> `C:/_PROYECTOS/Gaelco/research/METODO-GOLDEN-PYTHON.md`. Herramientas genéricas reutilizadas
> tal cual en `debug/` (`collect.py`, `compare.py`). Sim primario: **Verilator** (WSL).

## 1. La idea
Antes de confiar en el RTL/HW, escribir un **Python pequeño y sin dependencias** que **replica bit a
bit** el `screen_update` del referente (aquí: `cdp1869_device::screen_update` + `draw_char`/`draw_line`,
`reference/mame/cdp1869.cpp`) desde **los mismos datos** (volcado de escena: PAGE RAM + CHAR RAM +
PCB RAM + registros out3..out7). Eso da un PNG **"golden"** = oráculo pixel-exacto. Luego se compara
el RTL (modo REPLAY: escena precargada, **CPU en reset**) contra el golden píxel a píxel (SAD + barrido
de offset).

**Por qué funciona:** desacopla "¿entiendo el formato del CDP1869?" (lo valida el python, rápido) de
"¿mi RTL está bien?" (sólo tiene que igualar un referente conocido). El barrido de offset (dx,dy)
distingue: mínimo limpio ~(0,0) = OK; mejor offset≠0 = fase de pipeline calibrable (no bug);
suelo de SAD que no baja = bug de contenido real.

## 2. Cadena de validación (respetar el orden)
`golden == mame` (oráculo fiel) → `sim == golden` (RTL correcto) → `hw == sim` (build/.mra OK).
**Si falla el primer eslabón, arregla el golden primero — no diagnostiques el RTL.**

## 3. Estructura (modelo canónico, ya creada)
```
debug/destryer/
  oracle/      lua de MAME que vuelca la escena (page/char/pcb RAM + out3..7) + snapshot PNG
  dumps/       volcados .hex de escena (page_ram.hex, char_ram.hex, pcb_ram.hex, regs.hex)
  raw/         capturas EN CRUDO por fuente (numeración nativa):
    mame_snaps/ golden_python/ sim_snaps/ hw_snaps/
  scenes.txt   manifiesto: qué frame de cada fuente = cada ESCENA
  scenes/      salida unificada por escena (la genera collect.py)
  compare/     diffs (los genera compare.py)
debug/collect.py  debug/compare.py   debug/lib/   (genéricos, reutilizados de Gaelco)
tools/   cap_destryer.sh (orquestador), destryer_golden.py, destryer_sim_prep.py
```

## 4. Flujo paso a paso (Cidelsa)
1. **Volcar escena de MAME** (`debug/destryer/oracle/cap_scene_destryer.lua`, lanzado por
   `tools/cap_destryer.sh`): en un frame concreto vuelca a `dumps/` el estado que el RTL necesita —
   **PAGE RAM** (1K, vía `vis.spaces["pageram"]`), **CHAR RAM** (2K) y **PCB RAM** (2K) — y los
   **registros out3..out7**. Además vuelca el **bitmap CRUDO** de la pantalla a `dumps/screen.bin`.
   > ⚠️⚠️ **LECCIONES CRÍTICAS (ganadas a pulso, 2026-06-29):**
   > - **CHAR/PCB RAM no son shares**: se reconstruyen por **TAP de escrituras** a 0xF400-0xF7FF (misma
   >   fórmula que `cidelsa_charram_w`). **Retener los objetos tap en una tabla global** o el GC los
   >   desinstala silenciosamente (síntoma: 0 escrituras capturadas).
   > - **NO usar `scr:snapshot()` como oráculo pixel-exacto**: aplica el escalado de
   >   `set_default_position` (aspecto PAL 1.226×1.4) **+ filtrado bilinear** → colores intermedios y
   >   contenido reescalado. **Usar `scr:pixels()`** (bitmap crudo de la visarea, 294×294×4 BGRA) →
   >   pixel-exacto. Lanzar MAME con `-nosnapbilinear` igualmente.
   > - **Orientación**: el bitmap crudo del 1870 ya es la orientación nativa; el golden con `--rot none`
   >   casa 0.00%. El ROT90 del mueble es **cosmético** (no rotar para comparar).
   > - **Config de display** (freshorz/fresvert/line9...): el juego reescribe out5 ~1/frame (cmem para
   >   cargar chars) → muestrear "a fin de frame" da transitorios. Verificada para `tabla`:
   >   `freshorz=1 fresvert=1 line9=1 dblpage=0 bkg=2 col=0 cfc=0 hma=0`. (La auto-captura aún muestrea
   >   mal estos campos — PENDIENTE; de momento se fija el valor verificado en `regs.txt`.)
   > - Elegir escena **estática** (snapshot y volcado pueden ir 1 frame desfasados).
2. **Golden python** (`tools/destryer_golden.py`): lee los `dumps/*.hex` y **replica `screen_update`
   exactamente** (escaneo desde `hma`, `code=page[pma]`, `char=charram[(code<<3)|line]`, 6px de bits[5:0]
   MSB-first, ccb0=bit6/ccb1=bit7/pcb=pcbram, `get_pen`→paleta 72→RGB pesos 30/59/11; doblado por
   freshorz/fresvert). Escritor PNG a mano (`zlib`+`struct`, sin PIL/numpy). Salida → `raw/golden_python/`.
3. **Validar golden vs MAME**: `python debug/collect.py destryer <escena>` →
   `python debug/compare.py scenes/<escena>/mame.png scenes/<escena>/golden.png compare/<escena>_g-vs-mame`.
   Si coinciden, el formato es correcto y tenemos oráculo fiable.
4. **Replay del RTL (Verilator)**: `sim/verilator/sim_main.cpp` precarga los mismos `dumps/*.hex` en la
   BRAM del RTL (PAGE/CHAR/PCB) + carga los registros out3..7, mantiene **CPU en reset**, corre N frames
   y vuelca PPM → `raw/sim_snaps/`. (Patrón portado de `FPGA/sim/verilator/`.)
5. **Diff RTL vs golden, iterar**: `collect.py` + `compare.py` (SAD/px + % diff). Barrido de offset para
   triar fase vs contenido. Iterar el RTL hasta `sim == golden`.

## 5. Herramientas
- **Sim**: Verilator 5.032 en **WSL** (`/usr/bin/verilator`). Build estilo `FPGA/sim/verilator/Makefile`
  (`--cc --exe --build -O3 --top-module <top> sim_main.cpp`). Icarus 12.0 (Windows) = smoke-test opcional.
- **Diff**: `debug/compare.py A.png B.png out_prefix` → `_diff.png` (rojo) + `_side.png` (A|B|diff) + %px (PIL).
- **Unificar**: `debug/collect.py destryer [escena]` lee `scenes.txt` y copia `raw/<fuente>/` →
  `scenes/<escena>/<fuente>.png`.
- **PPM→PNG**: `FPGA/scripts/ppm2png.ps1` (reutilizable).

## 6. Trampas (heredadas, aplican igual)
- Golden y RTL deben usar **EXACTAMENTE la misma entrada** (mismo volcado de escena).
- Validar el formato en **Python ANTES** de gastar una iteración de RTL (segundos vs minutos).
- Elegir escena que **ejercite** la pieza (un tilemap en blanco no valida nada; escoger una con
  caracteres y color variados, y a ser posible estática).
- Mantener el golden ligero (sin numpy/PIL para *generar*; PIL sólo para el *diff*).
- Distinguir artefacto-de-harness (preload/direccionamiento del sim) de bug-real del RTL.
</content>
