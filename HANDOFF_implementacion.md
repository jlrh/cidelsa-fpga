# Cidelsa "VIDEO SYSTEM-1" → FPGA / MiSTer — Documento de traspaso (handoff)

**Objetivo:** implementar en MiSTer los arcades de **Cidelsa** (hardware EFO): **Destroyer (1980),
Altair (1981), Altair II, Draco (1981)**. Este documento es **autocontenido**: reúne todo lo
investigado para retomar el trabajo en otra sesión sin contexto previo.

> **Empieza por aquí.** Los detalles ampliados están en los documentos enlazados al final (§12).

---

## 1. Resumen ejecutivo

- Plataforma COSMAC de RCA llamada por EFO **"VIDEO SYSTEM-1"** (esquema de F. Yago, 1980).
- **CPU: RCA CDP1802.** **Vídeo: RCA CDP1869 (direcciones+sonido) + CDP1870 (color).** Pantalla
  **vertical (ROT90)**, ~50 Hz PAL, tilemap de caracteres en color (no framebuffer).
- **Draco** añade CPU de sonido **COP402 + AY‑3‑8910**; el resto comparte arquitectura.
- **Estado emulación (MAME):** los 4 son **jugables** (`destryer`/`altair`/`altair2` = imperfect sound;
  `draco` = imperfect colors). Driver: `efo/cidelsa.cpp`.
- **Estado FPGA:** **no existe core previo** de esta plataforma. El **CDP1802 es reutilizable** (cores
  GPL/MIT); el **CDP1869/1870 hay que escribirlo desde cero** (no existe en HDL en ningún sitio) — es
  el grueso del trabajo.
- **Documentación de placa:** tenemos el **esquema eléctrico completo** y el **BOM** (manual de
  Destroyer) y el **esquema de Altair**, guardados en `cidelsa/docs/`.

---

## 2. Datos de hardware por juego (verificados en MAME 0.288)

| Juego | Set | Año | CPU (reloj) | Vídeo (dot clk) | Sonido | ROM prog | Estado |
|---|---|---|---|---|---|---|---|
| Destroyer | `destryer` (+`destryera`) | 1980 | CDP1802 @ 3.579 MHz | CDP1869+1870 @ 5.7143 MHz | CDP1869 (tono+ruido) | 8 KB (4×2716) | imperfect sound |
| Altair | `altair` | 1981 | CDP1802 @ 3.579 MHz | @ 5.626 MHz | CDP1869 | 12 KB (6×2716) | imperfect sound |
| Altair II | `altair2` | 198? | CDP1802 @ 3.579 MHz | @ 5.626 MHz | CDP1869 | 12 KB | imperfect sound |
| Draco | `draco` | 1981 | CDP1802 @ 4.4336 MHz | @ 5.626 MHz | COP402 + AY‑3‑8910A @ 2.0122 MHz | 16 KB (8×2716) + 2 KB snd | imperfect colors |

Pantalla en todos: raster, **ROT90**, 294×294 lógico, ~50 Hz.

**Reproducir extracción:** `mame -listxml draco destryer altair altair2` → leer `<chip>` (clock),
`<display>`, `<driver status>`. (MAME local en `C:/MAME/mame.exe`, v0.288.)

---

## 3. Inventario de chips (BOM definitivo, manual de Destroyer)

Numeración 1–25 del BOM, repartida en placas. (Detalle completo: `cidelsa/altair_chips.md`.)

**Placa M.P.U.:**
```
1   CDP1802            CPU COSMAC            (XTAL 3.579 MHz)
2,3 2× RAM 5101        NVRAM 256×4 + bat NiCd 90mAh (marcador, 256 B)
4-7 4-8× ROM 2716      programa (Destroyer 4 / Altair 6 / Draco 8)
8,9 2× CDP1859         decodificador/latch de direcciones
```
**Placa V.I.S. (vídeo/sonido/I-O) — la pieza a implementar:**
```
10   CDP1869           address gen + sound  (XTAL 5.626 MHz)
16   CDP1870           color video gen      (salida a placa R.G.B.)
11,12,19,20  4× 2114   SRAM (page + char RAM)
15,21        2× 2102   SRAM (complemento page/char)
17,18  2× CDP1856      buffers de bus de datos
22,23  2× CDP1852 (IN) puertos de entrada (mandos/monedas/DIP); Altair añade un 4º
24     CDP1852 (OUT)   puerto de salida (contadores de moneda, etc.)
25     CD4025          triple NOR (glue)
```
**Placa FUENTE:** 7805 (regulador +5V), LM383 (audio), CD4020B (contador), transistores/diodos.
**Placa ADJUST:** 3× tiristor C‑106‑F, DIP **BT‑8** (config), pot. volumen, pulsador TEST.
**Conexión por postes** (A1‑A6, B1‑B5, C1‑C8, D1‑D8, S1‑S8) — **no es JAMMA**.

Diseño "COSMAC de catálogo": casi todo chips RCA 18xx, **mínima TTL**.

---

## 4. Mapa de memoria de la CPU (de `efo/cidelsa.cpp`)

| Juego | ROM programa | NVRAM | CDP1869 char map | CDP1869 page map |
|---|---|---|---|---|
| Destroyer | 0x0000‑0x1FFF | 0x2000‑0x20FF | 0xF400‑0xF7FF | 0xF800‑0xFFFF |
| Destroyer set2 | 0x0000‑0x1FFF | 0x3000‑0x30FF | 0xF400‑0xF7FF | 0xF800‑0xFFFF |
| Altair / Altair II | 0x0000‑0x2FFF | 0x3000‑0x30FF | 0xF400‑0xF7FF | 0xF800‑0xFFFF |
| Draco | 0x0000‑0x3FFF | 0x8000‑0x83FF | 0xF400‑0xF7FF | 0xF800‑0xFFFF |
| Draco sonido (COP402) | 0x000‑0x3FF (banco 2716 por A10) | — | — | — |

**I/O (puertos OUT del 1802, N0‑N2 = 3..7):** out3‑out7 = registros del CDP1869/1870 (ver §6).
Entradas/salidas vía **CDP1852** (Altair/Draco) o directo (Destroyer port 0x01/0x02).

---

## 5. Dos dominios de reloj (¡importante!)

- **CPU 1802:** cristal propio **3.579 MHz** (Draco 4.4336) en la M.P.U.
- **Vídeo 1869/1870 + RAM:** cristal **5.626 MHz** (PAL) en la V.I.S.
- **NO** se cumple CPUCLK = dot/2; son independientes. Sincronía CPU↔vídeo por **TPA/TPB** (mux de
  dirección) y por la **interrupción `_PREDISPLAY`/`_DISPLAY`** (1870 → `_INT` del 1802).
- PAL: Fh = 5.626e6/360 ≈ 15.63 kHz; Fv ≈ 50.09 Hz.

---

## 6. Mapa de registros del CDP1869/1870 (out3‑out7) — bits exactos (MAME)

| Reg | N | Función | Bits |
|---|---|---|---|
| out3 | 3 | Display/color | `[2:0]` bkg · `[3]` CFC · `[4]` dispoff · `[6:5]` col · `[7]` freshorz |
| out4 | 4 | Tono | `[3:0]` amp · `[6:4]` octava · `[7]` off · `[14:8]` divisor |
| out5 | 5 | Formato + ruido | `[0]` cmem · `[3]` line9 · `[5]` line16 · `[6]` dblpage · `[7]` fresvert · `[11:8]` wnamp · `[14:12]` wnfreq · `[15]` wnoff |
| out6 | 6 | Dirección PAGE | `[10:0]` pma (0x7FF) |
| out7 | 7 | Dirección CHAR/HMA | `[10:2]` hma (0x7FC) |

- Tono: `freq = (clk/2)/(512>>octava)/(divisor+1)`.
- **Ruido blanco: MAME NO lo implementa (TODO)** → en FPGA es un **LFSR** (datasheet RCA).

---

## 7. Color / RGB (salida del core)

Por píxel: `ccb0`(=BUS7), `ccb1`(=BUS6), `pcb`, + `col`(out3[6:5]), `CFC`(out3[3]), `bkg`(out3[2:0]).
```
col=0: r=ccb0,b=ccb1,g=pcb   col=1: r=ccb0,b=pcb,g=ccb1   col=2/3: r=pcb,b=ccb0,g=ccb1
color3 = (r<<2)|(b<<1)|g
pen = (CFC==0) ? color3 : color3 + (bkg+1)*8        // paleta 72 = 8 + 64
luma = ((l&4)?30:0)+((l&1)?59:0)+((l&2)?11:0); comp = luma*255/100   // pesos R30/G59/B11
```
En la placa el color digital → **placa R.G.B.** (DAC transistores) → monitor. En FPGA: paleta de 72 y
RGB directo (al scaler MiSTer). **No** hace falta replicar LUM/CHROM del CDP1870.

---

## 8. Memorias de vídeo

| Memoria | Contenido | Dirección | Chips | Notas |
|---|---|---|---|---|
| PAGE RAM | código de carácter por celda (40×24) | PMA0‑10 (out6) | 2× 2114 (IC11,12) | dblpage=0 ⇒ 10 bits |
| CHAR RAM | patrón 6px + color del carácter | {código}+CMA0‑3 (línea) | 4× 2114 + 2× 2102 | dblpage=1 ⇒ CMA 3 bits |

**CHAR RAM es escribible:** la CPU carga el generador de caracteres al arrancar. El HDL debe permitirlo.

---

## 9. Temporización (constantes MAME)

| | NTSC | PAL (Cidelsa) |
|---|---|---|
| Dot clock | 5.670 MHz | **5.626 MHz** |
| Líneas totales | 262 | **312** |
| Display (líneas) | 36–228 (192 vis) | 44–260 (216 vis) |
| Ancho celda | 6 px | 6 px |
| Columnas/Filas | 40×24 | 40×25 (half 20×12) |
| Ancho total línea | 60×6 = 360 dots | 360 dots |
| HSYNC / HBLANK | 56–60×6 / 54×6…5×6 | igual |
| Pantalla (col) | 10×6 … 50×6 | igual |

Celda 6×8 (NTSC) / 6×9 (PAL); con freshorz/fresvert=0 se duplica. **ROT90** (lo puede hacer el scaler MiSTer).

---

## 10. Cores HDL reutilizables y andamiaje MiSTer

**CDP1802 (CPU):**
- `wel97459/FPGACosmacVIP` y `FPGACosmacELF` — SpinalHDL→Verilog, GPL‑3.0, **ciclo‑exacto con DMA‑out probado** (mejor base).
- `brouhaha/cosmac` — VHDL, GPL‑3.0 (DMA‑out/IRQ a endurecer).
- `zpekic/Sys_180X` — VHDL, MIT (DMA‑out/IRQ sin documentar).
- `jamesbowman/verilog1802` — BSD, **no sirve** (sin DMA ni IRQ).
- **Requisito duro:** DMA‑out correcto (el 1869, como el 1861, vuelca pantalla por DMA del 1802).

**Andamiaje MiSTer:** `JasonA-dev/RCAStudioII_Mister` (RCA Studio II) — trae `cdp1802.v` + template
MiSTer ya cableado (WIP). Ahorra integrar CPU + framework.

**CDP1869/1870:** **a escribir desde cero.** Referencias: device MAME `src/devices/sound/cdp1869.{h,cpp}`
(registros/paleta/timing) + datasheet RCA VIS (ruido). Emma02 como cross‑check de comportamiento
(`emma02.hobby-site.com/cidelsa.html`).

**AY‑3‑8910 (Draco):** hay cores MiSTer de sobra. **COP402 (Draco):** verificar disponibilidad HDL.

---

## 11. Plan de implementación (orden sugerido)

1. **Framework MiSTer + CDP1802** (base RCAStudioII o wel97459 sobre template limpio). Validar CPU con DMA/IRQ.
2. **Sistema base:** mapa de memoria §4, ROM 2716, NVRAM 5101, decodificación (CDP1859), I/O CDP1852, DIP.
3. **Vídeo — timing** (dominio 5.626 MHz): contadores H(0..359)/V(0..311), _HSYNC/_DISPLAY/_PREDISPLAY, ventana visible.
4. **Vídeo — registros** out3‑out7 (§6).
5. **Vídeo — fetch:** PMA→PAGE RAM→código; {código,línea}→CHAR RAM→6px+color.
6. **Vídeo — color** (§7): paleta 72 → RGB. Doblado px/línea; ROT90 (scaler).
7. **Sonido:** tono (out4) + **ruido LFSR** (out5, del datasheet) → mezcla. Draco: COP402+AY‑3‑8910.
8. **Sincronía CPU↔vídeo:** _PREDISPLAY→_INT; arbitraje de acceso CPU/refresco a PAGE/CHAR RAM (TPA/TPB).
9. **Verificación:** comparar contra MAME (`destryer`/`altair`/`altair2`/`draco`) y Emma02.

---

## 12. Documentos del proyecto (dónde está cada cosa)

| Fichero | Contenido |
|---|---|
| `referencia_cidelsa_mame.md` (raíz) | Visión general de la plataforma, contexto histórico, fuentes |
| `cidelsa/altair_chips.md` | Inventario de chips / BOM completo por placas + mapa de páginas del manual |
| `cidelsa/cdp1869_signal_map.md` | **Mapa de señales detallado** (pinouts, registros, color, memorias, timing) para el HDL |
| `cidelsa/HANDOFF_implementacion.md` | **Este documento** (punto de entrada) |
| `cidelsa/docs/destroyer_manual_servicio.pdf` | Manual de servicio Destroyer: BOM (pág. 20/22/24/26), cableado (40), **esquema MONITOR (41)**, **esquema eléctrico VIDEO SYSTEM-1 (42)** |
| `cidelsa/docs/altair_esquematicos.pdf` | Esquema de placa "VIDEO ALTAIR" + esquema del monitor |

> Índice de páginas del PDF de Destroyer (PDF→manual: PDF = manual+2): pág. 42 PDF = **esquema
> eléctrico completo "VIDEO SYSTEM-1"** (el documento técnico más valioso); pág. 41 = monitor; pág. 40
> = cableado del sistema.

---

## 13. Cuestiones abiertas / correcciones a tener presentes

- **Draco — CPU de sonido:** MAME la modela como **COP402**; algunas fuentes (Arcade Database) dicen
  **COP420**. Confirmar en la línea `COP4xx(...)` de `cidelsa.cpp` si se va a emular su sonido con exactitud.
- **Dot clock de Destroyer:** MAME usa **5.7143 MHz**; el BOM del manual dice **5.626 MHz** (como Altair).
  Posible revisión o manual genérico. Medir/confirmar en placa.
- **Ruido blanco del CDP1869:** no está en MAME (TODO) → única referencia el datasheet (LFSR). Causa
  probable del flag *imperfect sound* en Destroyer/Altair.
- **Draco color (CDP1876 vs 1870):** Draco va etiquetado *imperfect colors* en MAME; el BOM de
  Destroyer/Altair monta **CDP1870**. Verificar si Draco usa CDP1876 (RGB) — afectaría a la salida de color.
- **EFO ubicación:** c/ María Barrientos, **Barcelona** (no Sant Andreu de la Barca, dato que circula sin confirmar).
- **Reparto exacto page‑vs‑char RAM** (qué bits en qué 2114/2102): no trazado pin a pin del escaneo;
  cerrar contra el esquema VIDEO SYSTEM-1 (pág. 42) en alta resolución si hace falta.

---

## 14. Fuentes externas clave

- MAME: `src/mame/efo/cidelsa.cpp`, `src/devices/sound/cdp1869.{h,cpp}` (github.com/mamedev/mame).
- Datasheet RCA "CDP1869/1870/1876 VIS": cosmacelf.com/publications/data-sheets/cdp1869.pdf (TLS
  caducado, abrir aceptando aviso) o databooks RCA en bitsavers.org.
- Emma02 (emulador, cross‑check Cidelsa): emma02.hobby-site.com/cidelsa.html
- Esquemas/manuales originales: recreativas.org (fichas `destroyer-4-cidelsa`, `altair-2-cidelsa`).
- Cores 1802: github.com/wel97459/FPGACosmacVIP · /FPGACosmacELF · github.com/brouhaha/cosmac ·
  github.com/zpekic/Sys_180X · andamiaje MiSTer: github.com/JasonA-dev/RCAStudioII_Mister.
