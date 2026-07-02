#!/usr/bin/env python3
# screenbin_to_png.py — convierte el volcado CRUDO de pixels de MAME (scr:pixels(),
# RGB32) a PNG. Es el GOLDEN independiente (no nuestra reimplementación golden-python).
#   python screenbin_to_png.py <screen.bin> <W> <H> <out.png>
# MAME BITMAP_FORMAT_RGB32 = 0xAARRGGBB little-endian -> bytes [B,G,R,A] por pixel,
# row-major (orientación CRUDA del CDP1870, = golden-python rot=none).
import sys, struct, zlib

def write_png(path, rows):
    h=len(rows); w=len(rows[0])
    raw=bytearray()
    for r in rows:
        raw.append(0)
        for (R,G,B) in r: raw += bytes((R,G,B))
    def chunk(t,d): return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d)&0xffffffff)
    with open(path,"wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR",struct.pack(">IIBBBBB",w,h,8,2,0,0,0)))
        f.write(chunk(b"IDAT",zlib.compress(bytes(raw),9)))
        f.write(chunk(b"IEND",b""))

def main():
    if len(sys.argv)<5: print("uso: screenbin_to_png.py <screen.bin> <W> <H> <out.png>"); sys.exit(1)
    binp, W, H, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    data=open(binp,"rb").read()
    need=W*H*4
    if len(data) < need:
        print(f"[!] screen.bin {len(data)} bytes < {need} esperados ({W}x{H}x4)"); sys.exit(1)
    rows=[]
    for y in range(H):
        row=[]
        for x in range(W):
            i=(y*W+x)*4
            B,G,R,A = data[i],data[i+1],data[i+2],data[i+3]
            row.append((R,G,B))
        rows.append(row)
    write_png(out, rows)
    print(f"golden MAME escrito: {out} ({W}x{H})")

if __name__=="__main__": main()
