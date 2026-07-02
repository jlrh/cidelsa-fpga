# Banco multimodo de vídeo CDP1869/1870 — escenas validadas

Driver: `tools/bench_video.sh <scene_dir>`. Golden crudo de MAME = `screen.bin` → `screenbin_to_png.py`.
Captura: `oracle/cap_cidelsa.lua` (config robusta: snapshot en OUT3/OUT5-cmem0). Inputs: `cap_gameplay.lua`.

| escena (dir)        | juego     | modo                          | RTL vs MAME | nota |
|---------------------|-----------|-------------------------------|-------------|------|
| dumps/              | Destroyer | alta-res, dblpage=0           | 0.00%       | tabla attract (estable) |
| altair/             | Altair    | alta-res, dblpage=1           | 0.00%       | título "VENCE BATALLA" |
| altair2/            | Altair    | alta-res, dblpage=1           | 0.03%       | f150, micro-animación |
| gameplay/           | Destroyer | baja-res (fhz/fvt/l9=0)       | 3.32%*      | *RTL==golden-python 0.00%; 3.32% = sync captura (dinámica) |

Cobertura: dblpage 0 y 1, alta y baja-res, 2 juegos. Pendiente: col=1/2/3, cfc, line16 (escenas que los usen);
escena ESTÁTICA baja-res para golden MAME limpio. Draco: direccionamiento de char DISTINTO (pmd<<3 sin
column=0xff) → necesita variante en el RTL para validarlo.

## Modos de COLOR validados (2026-06-30)
Destroyer y Altair usan SOLO col=0 y col=1 (attract+gameplay). col=2/3/cfc/line16 no los usa ningún juego.
| modo    | validación            | nota |
|---------|-----------------------|------|
| col=0   | RTL vs MAME 0.00%     | tabla/altair/gameplay-sea |
| col=1   | RTL vs MAME 0.07%     | Destroyer/Altair gameplay (play_col1/) |
| col=2   | RTL vs golden-py 0.00%| sintético (sin escena de juego; col2==col3 en get_pen) |
| col=3   | RTL vs golden-py 0.00%| sintético |
| cfc=1   | RTL vs golden-py 0.00%| sintético (paleta tono-sobre-tono) |
| line16=1| RTL vs golden-py 0.00%| sintético |
Para validar col=2/3/cfc DIRECTAMENTE vs MAME haría falta Draco (juego de color) → necesita variante RTL de direccionamiento.

## DRACO (3er juego) — direccionamiento distinto, validado (2026-06-30)
Draco usa char addressing DISTINTO: `addr=(pmd<<3)|cma` (sin column=0xff) + page RAM 2KB.
RTL: `vis_video` tiene input `draco` (charsel=pmd; page_addr 11 bits). golden-python: flag draco.
Captura: `oracle/cap_draco.lua` (char mirror pmd-directo, page 2KB, draco=1 en regs).
| escena (dir)   | modo                    | RTL vs MAME | nota |
|----------------|-------------------------|-------------|------|
| draco_col2/    | **col=2**, dbl=1, 2KB   | **0.00%**   | ¡col=2 directo vs MAME! (Draco f95, estático) |
| draco/         | col=0, dbl=1, 2KB       | 3.45%       | f400 dinámico (sync captura); col=2 prueba el addressing |
Draco usa col=0/1/2 (cfc=0). col=2==col=3 en get_pen → col=3 cubierto. Para un CORE Draco completo
falta COP402+AY8910 + su mapa de memoria (esto valida solo el VÍDEO).
