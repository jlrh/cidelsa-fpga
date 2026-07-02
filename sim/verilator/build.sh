#!/usr/bin/env bash
# Build + run de un harness Verilator de bloque. Pensado para WSL (verilator 5.x).
#   uso:  ./build.sh <top_module> <main.cpp> [rtl1.v rtl2.v ...]
#   ej:   ./build.sh vis_video_timing tb_video_timing.cpp ../../rtl/vis_video_timing.v
set -e
TOP="$1"; MAIN="$2"; shift 2
VSRC="$@"
OUTDIR="obj_${TOP}"
VFLAGS="--cc --exe --build -j 0 -O3 --top-module ${TOP} -CFLAGS -O1 \
  -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-UNUSED -Wno-PINMISSING"
verilator ${VFLAGS} --Mdir ${OUTDIR} ${VSRC} ${MAIN} -o ${TOP}_sim
echo "=== run ==="
./${OUTDIR}/${TOP}_sim
