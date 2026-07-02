#!/usr/bin/env python3
# compare.py — diff visual entre dos imagenes (dos fuentes de la MISMA escena).
#   python compare.py <A.png> <B.png> [out_prefix]
# Genera:
#   <out>_diff.png  = A con los pixeles que difieren marcados en ROJO (amplificado)
#   <out>_side.png  = A | B | diff  (lado a lado para inspeccion)
# e imprime el % de pixeles que difieren. A = referencia (p.ej. mame/golden), B = a evaluar (sim/hw).
import sys, os
from PIL import Image, ImageChops

def main():
    if len(sys.argv) < 3:
        print("uso: compare.py <A.png> <B.png> [out_prefix] [umbral]"); sys.exit(1)
    A = Image.open(sys.argv[1]).convert('RGB')
    B = Image.open(sys.argv[2]).convert('RGB')
    out = sys.argv[3] if len(sys.argv) > 3 else os.path.splitext(sys.argv[2])[0]
    thr = int(sys.argv[4]) if len(sys.argv) > 4 else 24
    if B.size != A.size:
        B = B.resize(A.size, Image.NEAREST)
    W, H = A.size
    da = A.load(); db = B.load()
    diff = A.copy(); dd = diff.load()
    ndiff = 0
    for y in range(H):
        for x in range(W):
            ra,ga,ba = da[x,y]; rb,gb,bb = db[x,y]
            if abs(ra-rb)+abs(ga-gb)+abs(ba-bb) > thr:
                dd[x,y] = (255,0,0); ndiff += 1
    diff.save(out+"_diff.png")
    side = Image.new('RGB', (W*3+8, H), (0,0,0))
    side.paste(A,(0,0)); side.paste(B,(W+4,0)); side.paste(diff,(W*2+8,0))
    side.save(out+"_side.png")
    pct = 100.0*ndiff/(W*H)
    print(f"diff {sys.argv[1]} vs {sys.argv[2]}: {ndiff}/{W*H} px ({pct:.2f}%) > {thr}")
    print(f"  -> {out}_diff.png  (rojo = difiere)")
    print(f"  -> {out}_side.png  (A | B | diff)")

if __name__=='__main__': main()
