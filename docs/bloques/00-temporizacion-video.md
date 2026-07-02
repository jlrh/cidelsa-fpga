# Bloque 0 — Temporización de vídeo (CDP1870, PAL)

**RTL:** `rtl/vis_video_timing.v` · **Harness:** `sim/verilator/tb_video_timing.cpp` ·
**Estado:** ✅ VALIDADO (12/12 checks, 2026-06-29)

## Qué hace
Genera la rejilla de raster PAL del CDP1869/1870 a partir de un `ce_pix` (un dot por pulso).
Fuente de verdad: constantes `set_raw` + `screen_update` de `reference/mame/cdp1869.h/.cpp`.

## Constantes (PAL, CH_WIDTH=6)
| | dots / scanlines |
|---|---|
| H_TOTAL | 360 (= 60·6) |
| HSYNC | [336, 360) (56·6 .. 60·6) — 24 dots |
| HBLANK activo-vídeo | [30, 324) (5·6 .. 54·6) |
| H área caracteres | [54, 300) (9·6 .. 50·6) |
| V_TOTAL | 312 |
| VSYNC | [308, 312) — 4 líneas |
| VBLANK activo-vídeo | [10, 304) |
| V área caracteres | [44, 260) |
| PREDISPLAY (PRD=1) | [43, 260) |

## Señales de salida
- `hcount[8:0]` 0..359, `vcount[8:0]` 0..311.
- `hsync`/`vsync` activo-ALTO en su ventana (el wrapper invierte si el scaler los quiere bajo).
- `hblank`/`vblank` = fuera de vídeo activo.
- `de` = ventana visible **294×294** (= [30,324)×[10,304)) — lo que captura el scaler MiSTer.
- `display` = área de caracteres (inner) donde el bloque 3 pinta el tilemap; fuera de ella pero
  dentro de `de` se pinta el color de fondo `bkg`.
- `predisplay` (PRD) y `prd_int = ~PRD`. **`prd_int` → INT y EF1 del 1802** (misma señal, como
  `cidelsa_state::prd_w`): activos en vblank → es la IRQ de frame del juego.

## Validación (harness autoverificable)
`dots/frame=112320`, `de=86436 (294²)`, `display=53136 (246×216)`, `hsync=24 dots/línea×312`,
`vsync=4 líneas`, PRD sube en v=43 y baja en v=260, `prd_int==~predisplay`. **TODO OK.**

Build/run (WSL):
```
cd sim/verilator && ./build.sh vis_video_timing tb_video_timing.cpp ../../rtl/vis_video_timing.v
```

## Notas / pendientes
- El dot clock real (5.7143 Destroyer / 5.626 PAL) lo aporta el wrapper vía `ce_pix`; el módulo
  es independiente de la frecuencia. Fv ≈ 50.9 / 50.09 Hz respectivamente.
- Doblado de píxel/línea (freshorz/fresvert) NO va aquí: es del bloque de fetch/pintado (3).
- Parámetros NTSC quedan como override de los `parameter` (los juegos Cidelsa son PAL).
</content>
