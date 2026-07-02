# Estado del proyecto Cidelsa y cómo retomarlo

> **Punto de entrada.** Última actualización: 2026-06-29 (sesión de arranque).

## 1. Resumen en una línea
Core **MiSTer de la plataforma Cidelsa "VIDEO SYSTEM-1"** (COSMAC: CDP1802 + CDP1869/1870),
**desde cero** en Verilog (método clon del core Galaxian). Primer target: **Destroyer**.
4 juegos objetivo: Destroyer, Altair, Altair II, Draco.

## 2. Estado actual (qué hay hecho)
- ✅ **Decisiones de rumbo** (con el usuario): framework = estilo Galaxian desde cero;
  primer juego = Destroyer; sim primario = **Verilator** (WSL).
- ✅ **Referencia de oro descargada** (MAME 0.288) en `reference/mame/`: `cidelsa.{cpp,h}`,
  `cidelsa_v.cpp`, `cdp1869.{cpp,h}`, `cosmac.{cpp,h}`.
- ✅ **Arquitectura completa** en `docs/arquitectura.md` (mapa mem/IO, registros out3-7, formato
  de píxel, color/paleta 72, timing PAL, sonido, plan de 9 bloques). **Incluye corrección al
  handoff: NO hay DMA-out de vídeo** (el 1869 escanea su propia PAGE/CHAR RAM; la CPU sólo escribe
  por memoria) → relaja el requisito de CPU.
- ✅ **Metodología montada** en `docs/METODOLOGIA.md` + estructura `debug/destryer/` + herramientas
  genéricas `debug/{collect,compare}.py` (copiadas de Gaelco).
- ✅ **Bloque 0 — timing de vídeo** (`rtl/vis_video_timing.v`): VALIDADO con harness Verilator
  (12/12 checks). Ver `docs/bloques/00-temporizacion-video.md`. Flujo Verilator-WSL operativo
  (`sim/verilator/build.sh`).
- ✅ **Bloque 1 — registros out3-7** (`rtl/vis_regs.v`): VALIDADO (22/22). `docs/bloques/01-registros.md`.
- ✅ **ROMs Destroyer**: `C:/MAME/roms/destryer.zip` verificada (4 CRC OK, `mame -verifyroms` good).
- ✅🏆 **GOLDEN == MAME PIXEL-PERFECT (0.00%, 0/86436 px)** para la escena `tabla` (tabla de puntuación
  del attract). `tools/destryer_golden.py` replica `cdp1869::screen_update` exacto. Pipeline de volcado
  completo y funcionando (`cap_scene_destryer.lua` + `screen:pixels()`). Ver
  `debug/destryer/compare/tabla_VALIDADO_side.png`. **El oráculo de vídeo está LISTO.**
- ✅🏆 **Bloques 2 + 3 — VRAM + fetch + color** (`rtl/vis_vram.v`, `rtl/vis_palette.v`, `rtl/vis_video.v`):
  pipeline de vídeo completo. **VALIDADO `sim == golden == MAME` 0.00% (0/86436 px)** por replay Verilator
  (`sim/verilator/tb_video_replay.cpp`). Ver `docs/bloques/02-03-vram-fetch-color.md`. **El segundo
  eslabón de la cadena está cerrado.** Artefactos en `debug/destryer/compare/`.
- ✅🏆 **Bloque 5 — CPU CDP1802: ESCRITA DESDE CERO Y VALIDADA** `rtl/cpu/cdp1802_jl.v` (traducción de
  MAME `cosmac.cpp`). **200 primeras OUTs IDÉNTICAS vs MAME** (boot, SCRT anidado, NVRAM, delay loops,
  long branches+skips, INP/OUT, debounce de inputs). Cableada en `cidelsa_machine.v`. Oráculos:
  `io_trace.lua` + debugger `trace`. Ver `cpu-1802-desde-cero` (memoria).
- ✅🏆 **Bloques 4+6 — INTEGRACIÓN + SISTEMA VIVO**: `cidelsa_machine.v` integra CPU + vis_vram
  (compartida, direccionamiento 1869 CHAR/PAGE real) + vis_regs + vis_video. **La CPU integrada produce
  las 200 OUTs IDÉNTICAS a MAME corriendo vivo** + el vídeo renderiza. Harness `tb_live.cpp`. Bug de
  interrupción arreglado (IE post-instrucción). Ver `integracion-sistema-vivo` (memoria).
- ✅ **Bloque 7 — SONIDO** `rtl/vis_sound.v` (tono out4 + ruido LFSR out5): VALIDADO (tono = fórmula
  MAME exacta; ruido funcional). Cableado en `cidelsa_machine` (sistema vivo sigue 200 OUTs == MAME).
- ⬜ Bloque 8 (MiSTer) + calibración de timing visual.

## 3. Próximos pasos (al retomar, EMPEZAR AQUÍ)
1. **Bug de 2 códigos de char** (0xbe/0xff): el sistema vivo renderiza la tabla ~92% bien; solo el
   char del ESPACIO (0xff) y el borde (0xbe) están corruptos (los otros 254 códigos coinciden con
   MAME). Bug en la escritura de char para códigos altos (path `column=0xff`/`pma[10]`/dblpage).
   Instrumentar las escrituras a char_idx 0x5f0/0x7f8 (pma,column,data) vs MAME. Ver
   `integracion-sistema-vivo` (memoria).
2. **Calibrar timing**: el texto sale en posiciones distintas a la tabla exacta (offset de attract por
   la ratio ce aproximada). Sincronizar / capturar en frame estable.
3. **Wrapper MiSTer** + .mra + síntesis Quartus (convertir vis_video a BRAM registrada + prefetch).
2. **Bloque 4/6 — integración + sistema Destroyer**: cablear CPU + vis_regs (escrituras out3-7) +
   vis_vram (escrituras CPU a 0xF400-0xFFFF) + ROM 2716 + NVRAM + inputs/EF + INT(prd). Arrancar el
   juego "vivo" (no replay) y re-validar vídeo con la CPU real escribiendo las RAM.
3. **Síntesis MiSTer**: convertir `vis_video` (hoy combinacional async-read + div/mod) a BRAM
   registrada + contadores de celda + prefetch; calibrar offset de pipeline contra este golden.
4. PENDIENTE menor: la auto-captura de `regs.txt` muestrea mal freshorz/fresvert/line9 (transitorios
   de out5); de momento se fija la config verificada a mano.

## ⚠️ Lecciones del oráculo (NO repetir) — ver `docs/METODOLOGIA.md`
- MAME `scr:snapshot()` ESCALA (set_default_position aspecto PAL) + bilinear → **NO** es pixel-exacto.
  Usar **`scr:pixels()`** (bitmap crudo BGRA) + `-nosnapbilinear`.
- Los objetos `install_*_tap` se van por **GC** si no se retienen en una tabla global.
- CHAR/PCB RAM no son shares → reconstruir por tap de escrituras a 0xF400.
- Comparar en orientación CRUDA (golden `--rot none`); el ROT90 del mueble es cosmético.

## 4. Toolchain
- **Verilator 5.032** en WSL (`wsl -e bash -lc 'verilator ...'`). Build estilo `FPGA/sim/verilator/Makefile`.
- Icarus 12.0 + GTKWave en Windows (smoke-test rápido opcional).
- Quartus 17.0.x (síntesis MiSTer, fase final).
- MAME 0.288 en `C:/MAME/mame.exe` (oráculo). ROMs: las aporta el usuario (no en repo, copyright).

## 5. Mapa de ficheros del proyecto
```
HANDOFF_implementacion.md   handoff original (visión global, autocontenido)
altair_chips.md             BOM/inventario de chips
cdp1869_signal_map.md       mapa de señales/pinout para el HDL
docs/arquitectura.md        ⭐ documento maestro (verdad extraída de MAME)
docs/METODOLOGIA.md         flujo golden-python adaptado
docs/ESTADO.md              este fichero
docs/bloques/               un doc por bloque HDL
docs/*.pdf                  esquemáticos (Destroyer servicio + Altair)
reference/mame/             fuente MAME 0.288 (oráculo de comportamiento)
rtl/  sim/  debug/  tools/  golden/  roms/  mister/   (scaffold)
```
</content>
