#!/usr/bin/env python3
# ============================================================================
#  destryer_golden.py — golden-python: réplica EXACTA de cdp1869 screen_update.
# ----------------------------------------------------------------------------
#  Lee un volcado de escena (debug/destryer/dumps/) y reproduce, bit a bit, el
#  render del CDP1869/1870 (reference/mame/cdp1869.cpp: screen_update + draw_char
#  + draw_line + get_pen + paleta). Salida = PNG (oráculo pixel-exacto).
#
#  Sin dependencias (escritor PNG a mano con zlib+struct).
#  Uso:  python destryer_golden.py <dumps_dir> <out.png> [--rot cw|ccw|none]
#        --rot cw  => rota 90° horario para casar con el snapshot ROT90 de MAME.
# ============================================================================
import sys, os, zlib, struct

# ---- timing/área (PAL, cdp1869.h) ----
CH_WIDTH = 6
SCREEN_START_PAL = 9*CH_WIDTH      # 54
SCREEN_END       = 50*CH_WIDTH     # 300
DISP_START_Y     = 44
DISP_END_Y       = 260             # height = 216
HBLANK_END, HBLANK_START = 5*CH_WIDTH, 54*CH_WIDTH   # 30..324  (visible H)
VBLANK_END, VBLANK_START = 10, 304                    # 10..304  (visible V)
FRAME_W, FRAME_H = 360, 312

def load_hex(path, n):
    vals = [0]*n
    with open(path) as f:
        i = 0
        for line in f:
            line = line.strip()
            if line == "": continue
            if i < n: vals[i] = int(line, 16) & 0xff
            i += 1
    return vals

def load_regs(path):
    r = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                k,v = line.split("=",1); r[k] = int(v)
    return r

# ---- paleta de 72 (get_rgb + cdp1869_palette) ----
def get_rgb(c, l):
    luma = (30 if l & 4 else 0) + (59 if l & 1 else 0) + (11 if l & 2 else 0)
    luma = luma * 255 // 100
    return ( luma if c & 4 else 0, luma if c & 1 else 0, luma if c & 2 else 0 )

def build_palette():
    pens = [get_rgb(i, 15) for i in range(8)]          # 0..7 color-on-color
    for c in range(8):
        for l in range(8):
            pens.append(get_rgb(c, l))                  # 8..71 tone-on-tone
    return pens

def get_pen(ccb0, ccb1, pcb, col, cfc, bkg):
    if col == 0:   r,b,g = ccb0, ccb1, pcb
    elif col == 1: r,b,g = ccb0, pcb,  ccb1
    else:          r,b,g = pcb,  ccb0, ccb1
    color = (r << 2) | (b << 1) | g
    return color if not cfc else color + ((bkg + 1) * 8)

def get_lines(line16, line9, dblpage):
    if line16 and not dblpage: return 16
    if not line9:              return 9
    return 8

def main():
    if len(sys.argv) < 3:
        print("uso: destryer_golden.py <dumps_dir> <out.png> [--rot cw|ccw|none]"); sys.exit(1)
    dumps, out = sys.argv[1], sys.argv[2]
    # rot=none = orientación CRUDA del CDP1870 (= screen:pixels() de MAME, pixel-exacta).
    # Para verla "derecha" (ROT90 del mueble) usar --rot cw (sólo cosmético, NO para comparar).
    rot = "none"
    if "--rot" in sys.argv: rot = sys.argv[sys.argv.index("--rot")+1]
    # overrides de registros por CLI: key=val (para barrer config sin re-volcar MAME)
    overrides = {}
    for a in sys.argv[3:]:
        if "=" in a and not a.startswith("--"):
            k,v = a.split("=",1); overrides[k] = int(v)

    page = load_hex(os.path.join(dumps,"page_ram.hex"), 0x800)  # 2KB (Draco); Cidelsa rellena 1KB
    char = load_hex(os.path.join(dumps,"char_ram.hex"), 0x800)
    pcbr = load_hex(os.path.join(dumps,"pcb_ram.hex"),  0x800)
    reg  = load_regs(os.path.join(dumps,"regs.txt"))
    reg.update(overrides)
    pens = build_palette()

    bkg=reg["bkg"]; cfc=reg["cfc"]; col=reg["col"]; dispoff=reg["dispoff"]
    freshorz=reg["freshorz"]; fresvert=reg["fresvert"]
    line9=reg["line9"]; line16=reg["line16"]; dblpage=reg["dblpage"]; hma=reg["hma"]
    draco=reg.get("draco",0)   # 1=Draco (char vía pmd directo, sin column=0xff)
    lines = get_lines(line16, line9, dblpage)

    # framebuffer absoluto 360x312, relleno con el color de fondo (bkg)
    bg = pens[bkg]
    buf = [[bg]*FRAME_W for _ in range(FRAME_H)]

    def putpix(x, y, rgb):
        if 0 <= x < FRAME_W and 0 <= y < FRAME_H:
            buf[y][x] = rgb

    def draw_line(x, y, data, color):
        rgb = pens[color]
        d = (data << 2) & 0xff
        for _ in range(CH_WIDTH):
            if d & 0x80:
                putpix(x, y, rgb)
                if not fresvert: putpix(x, y+1, rgb)
                if not freshorz:
                    putpix(x+1, y, rgb)
                    if not fresvert: putpix(x+1, y+1, rgb)
            if not freshorz: x += 1
            x += 1
            d = (d << 1) & 0xff

    def draw_char(ax, ay, pma):
        pmd = page[pma & (0x7ff if draco else 0x3ff)]
        column = pmd if draco else (0xff if (pma & 0x400) else pmd)
        y = ay
        for cma in range(lines):
            ca  = ((column << 3) | (cma & 7)) & 0x7ff
            data = char[ca]
            ccb0 = (data >> 6) & 1
            ccb1 = (data >> 7) & 1
            pcb  = pcbr[((pmd << 3) | (cma & 7)) & 0x7ff]
            color = get_pen(ccb0, ccb1, pcb, col, cfc, bkg)
            draw_line(ax, y, data, color)
            y += 1
            if not fresvert: y += 1

    if not dispoff:
        width  = CH_WIDTH * (1 if freshorz else 2)
        height = lines    * (1 if fresvert else 2)
        cols = 40 if freshorz else 20
        rows = (DISP_END_Y - DISP_START_Y) // height
        pmemsize = cols * rows
        if dblpage: pmemsize *= 2
        if line16:  pmemsize *= 2
        addr = hma
        for sy in range(rows):
            for sx in range(cols):
                draw_char(SCREEN_START_PAL + sx*width, DISP_START_Y + sy*height, addr)
                addr += 1
                if addr == pmemsize: addr = 0

    # recortar a la ventana visible [30,324)x[10,304) = 294x294
    vis = [row[HBLANK_END:HBLANK_START] for row in buf[VBLANK_END:VBLANK_START]]

    # rotación para casar con el snapshot ROT90 de MAME
    if rot == "cw":
        h = len(vis); w = len(vis[0])
        vis = [[vis[h-1-x][y] for x in range(h)] for y in range(w)]
    elif rot == "ccw":
        h = len(vis); w = len(vis[0])
        vis = [[vis[x][w-1-y] for x in range(h)] for y in range(w)]

    write_png(out, vis)
    print(f"golden escrito: {out}  ({len(vis[0])}x{len(vis)})  rot={rot}  "
          f"lines={lines} cols={cols if not dispoff else '-'} rows={rows if not dispoff else '-'}")

def write_png(path, rows_rgb):
    h = len(rows_rgb); w = len(rows_rgb[0])
    raw = bytearray()
    for row in rows_rgb:
        raw.append(0)
        for (r,g,b) in row:
            raw += bytes((r,g,b))
    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        return c + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw),9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f: f.write(png)

if __name__ == "__main__":
    main()
