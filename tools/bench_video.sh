#!/usr/bin/env bash
# ============================================================================
#  bench_video.sh — banco MULTIMODO de validación del vídeo CDP1869/1870.
#  Valida que el RTL (vis_video) reproduce CADA modo de display, no solo la tabla.
#
#  Para una escena (dir con page_ram.hex char_ram.hex pcb_ram.hex regs.txt
#  [+ screen.bin de MAME]):
#   1) copia la escena a debug/destryer/replay_scene/ y corre el replay RTL (Verilator/WSL)
#      → debug/destryer/raw/sim_snaps/tabla.ppm
#   2) golden-python (oráculo, == MAME validado) → <scene>/golden_raw.png
#   3) si hay screen.bin → golden CRUDO de MAME → <scene>/mame_golden.png
#   4) compara RTL vs golden-python y (si hay) RTL vs MAME
#
#  Escenas:
#   - tabla    : debug/destryer/dumps/        (attract, alta-res, dblpage=0)  [estable]
#   - gameplay : debug/destryer/gameplay/     (título/score, BAJA-res fhz=0/fvt=0/l9=0)
#
#  Capturar más escenas/modos: con cap_scene_destryer.lua (attract) o cap_gameplay.lua
#  (inyecta moneda+start → otros modos). Para un golden de MAME LIMPIO hace falta una
#  escena ESTÁTICA (sin redibujado): en dinámicas el snapshot de VRAM no casa al píxel
#  con el screen.bin (sync de captura), aunque RTL==golden-python siga 0.00%.
#
#  uso: bench_video.sh <scene_dir> [W H]
# ============================================================================
set -e
ROOT=/c/_PROYECTOS/Cidelsa
SCENE="$1"; W="${2:-294}"; H="${3:-294}"
[ -z "$SCENE" ] && { echo "uso: bench_video.sh <scene_dir> [W H]"; exit 1; }
RS="$ROOT/debug/destryer/replay_scene"
mkdir -p "$RS"
cp "$SCENE"/page_ram.hex "$SCENE"/char_ram.hex "$SCENE"/pcb_ram.hex "$SCENE"/regs.txt "$RS/"

echo ">>> replay RTL ($SCENE)"
wsl -e bash -lc 'cd /mnt/c/_PROYECTOS/Cidelsa/sim/verilator && ./obj_replay/vis_replay 2>/dev/null' >/dev/null
SIM="$ROOT/debug/destryer/raw/sim_snaps/tabla.ppm"

python "$ROOT/tools/destryer_golden.py" "$RS" "$SCENE/golden_raw.png" --rot none >/dev/null
echo -n "    RTL vs golden-python : "; python "$ROOT/debug/compare.py" "$SCENE/golden_raw.png" "$SIM" "$SCENE/cmp_rtl_gp" | grep -oE "[0-9.]+%"

if [ -f "$SCENE/screen.bin" ]; then
  python "$ROOT/tools/screenbin_to_png.py" "$SCENE/screen.bin" "$W" "$H" "$SCENE/mame_golden.png" >/dev/null
  echo -n "    RTL vs MAME (crudo)  : "; python "$ROOT/debug/compare.py" "$SCENE/mame_golden.png" "$SIM" "$SCENE/cmp_rtl_mame" | grep -oE "[0-9.]+%"
fi
