#!/usr/bin/env python3
# collect.py — UNIFICA la nomenclatura: copia frames concretos de cada fuente (en raw/, con su numeracion
# nativa) a debug/<core>/scenes/<escena>/<fuente>.png, segun el manifiesto scenes.txt.
#
#   python collect.py <core> [escena]
#   (sin escena -> procesa TODAS las del manifiesto)
#
# Formato de debug/<core>/scenes.txt (una escena por linea; '#'=comentario):
#   <escena> : <fuente>=<frameid> <fuente>=<frameid> ...
#   p.ej.:  codo : mame=1200 golden=1200 sim=58 hw=20260625_091639
# Fuentes válidas = subcarpetas de raw/ (mame_snaps->'mame', golden_python->'golden', etc.; ver ALIAS).
import sys, os, glob, shutil

ROOT = os.path.dirname(os.path.abspath(__file__))
# alias corto -> subcarpeta raw/
ALIAS = {
    'mame':'mame_snaps', 'mame_tm':'mame_tilemap', 'mame_spr':'mame_sprites',
    'golden':'golden_python', 'golden_tm':'golden_tilemap', 'golden_spr':'golden_sprites',
    'sim':'sim_snaps', 'sim_tm':'sim_tilemap', 'sim_spr':'sim_sprites',
    'hw':'hw_snaps',
}

def find_raw(rawdir, frameid):
    # busca el fichero nativo que corresponde al frameid (flexible con el padding/prefijo)
    fid = str(frameid)
    pats = [f"{fid}.png", f"{int(fid):04d}.png" if fid.isdigit() else fid,
            f"frame_{fid}.png", f"frame_{int(fid):04d}.png" if fid.isdigit() else fid,
            f"cap_{fid}.png", f"*{fid}*.png"]
    for p in pats:
        m = sorted(glob.glob(os.path.join(rawdir, p)))
        if m: return m[0]
    return None

def main():
    if len(sys.argv) < 2:
        print("uso: collect.py <core> [escena]"); sys.exit(1)
    core = sys.argv[1]; only = sys.argv[2] if len(sys.argv) > 2 else None
    base = os.path.join(ROOT, core)
    manifest = os.path.join(base, "scenes.txt")
    if not os.path.exists(manifest):
        print(f"[!] no existe {manifest}"); sys.exit(1)
    for line in open(manifest, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#') or ':' not in line: continue
        scene, rest = line.split(':', 1)
        scene = scene.strip()
        if only and scene != only: continue
        outdir = os.path.join(base, "scenes", scene); os.makedirs(outdir, exist_ok=True)
        for tok in rest.split():
            if '=' not in tok: continue
            src, fid = tok.split('=', 1)
            sub = ALIAS.get(src, src)
            rawdir = os.path.join(base, "raw", sub)
            f = find_raw(rawdir, fid)
            if f:
                dst = os.path.join(outdir, src + ".png")
                shutil.copyfile(f, dst); print(f"  {scene}: {src} <- {os.path.basename(f)}")
            else:
                print(f"  {scene}: [!] no encontrado {src}={fid} en raw/{sub}/")
    print("collect listo.")

if __name__=='__main__': main()
