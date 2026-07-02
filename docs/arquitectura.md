# Cidelsa "VIDEO SYSTEM-1" — Arquitectura del core FPGA/MiSTer

> Documento maestro de arquitectura. Traduce la verdad de referencia (MAME 0.288 +
> esquemáticos) al plan de bloques HDL. Método: **clon del flujo del core Galaxian**
> (`C:/_PROYECTOS/FPGA`) — Verilog desde cero, `rtl/` + `sim/` (testbench por bloque),
> `docs/bloques/` (un doc por bloque), golden-python vs MAME, Quartus 17.0.x.
> **Sim primario: Verilator** (WSL, v5.032 — más completo y rápido que Icarus; Icarus
> queda como smoke-test rápido opcional). Validación: ver `docs/METODOLOGIA.md`.
> Primer target: **Destroyer**.

Fuente de referencia local (descargada, MAME 0.288): `reference/mame/`
- `cidelsa.cpp` / `cidelsa.h` / `cidelsa_v.cpp` — driver de placa (mapa mem/IO, ROMs, inputs, EF).
- `cdp1869.cpp` / `cdp1869.h` — **el chip a reimplementar** (timing, registros, scan, color, sonido).
- `cosmac.cpp` / `cosmac.h` — CPU CDP1802 (referencia de comportamiento).

---

## 0. Corrección importante al handoff: **NO hay DMA-out de vídeo**

El handoff §10 marca como "requisito duro" que el CDP1869 *vuelque la pantalla por DMA del 1802*
(como el CDP1861/Pixie). **Esto es incorrecto para el CDP1869.** En el modelo de MAME y en la placa:

- El CDP1869 es un **generador de tilemap de caracteres** con sus propias **PAGE RAM** y **CHAR RAM**
  (SRAM externa 2114/2102, pero **direccionada por el 1869**). El 1869 **escanea autónomamente** esa
  RAM para generar el vídeo — no necesita DMA de la CPU.
- La CPU accede a PAGE/CHAR RAM como **escrituras mapeadas en memoria** (0xF400–0xFFFF), que el 1869
  decodifica y arbitra con su mux de direcciones (TPA/TPB). No hay ciclo DMA-out para el display.

**Consecuencia para la elección de CPU:** NO necesitamos DMA-out del 1802. El core de CPU sólo
necesita: lectura/escritura de memoria (MRD/MWR), instrucciones **OUT/INP** con líneas **N0–N2**,
flags **EF1–EF4**, **INT**, salida **Q**. Esto relaja mucho el requisito (jamesbowman/verilog1802
falla por falta de IRQ/EF, no por DMA). Confirmar igualmente que el core elegido tiene INT+EF+Q+OUT.

---

## 1. Diagrama de bloques (Destroyer)

```
  clk_cpu (3.579 MHz)                 clk_dot (5.7143 Destroyer / 5.626 PAL)
        │                                   │
   ┌────▼─────┐   OUT N0-2 / data    ┌──────▼──────────────────────────────┐
   │ CDP1802  │─────────────────────►│  CDP1869/1870 "VIS" (a escribir)     │
   │  (CPU)   │   MRD/MWR, A[15:0]    │  ┌─ timing H(0..359)/V(0..311) PAL   │
   │          │◄──INT,EF1 (PRD)──────┤  ├─ registros out3..out7             │
   └────┬─────┘                       │  ├─ PAGE RAM (1K×8) scan @ hma       │
        │ data bus                    │  ├─ CHAR RAM (2K×8) {code<<3|line}   │
   ROM 2716 (8KB, 0x0000-0x1FFF)      │  ├─ PCB RAM (2K×1, latch de Q)       │
   NVRAM 5101 (256B, 0x2000-0x20FF)   │  ├─ color → paleta 72 → RGB          │
   inputs (IN0/IN1)                   │  └─ sonido: tono + ruido(LFSR)       │
                                      └──────────────┬──────────────────────┘
                                              R/G/B + HS/VS  →  scaler MiSTer (ROT90)
```

Dos dominios de reloj **independientes** (no CPUCLK=DOT/2 aquí). Sincronía CPU↔vídeo sólo por
**PRD→INT/EF1** (interrupción de predisplay/vblank). El acceso CPU a PAGE/CHAR RAM se arbitra con
el escaneo de vídeo (en FPGA: dual-port BRAM, puerto A = CPU, puerto B = scan de vídeo).

---

## 2. Mapa de memoria CPU (Destroyer — `destryer_map`)

| Rango | Destino | Notas |
|---|---|---|
| `0x0000–0x1FFF` | ROM programa (4×2716 = 8KB) | set `destryer`; set2 igual |
| `0x2000–0x20FF` | NVRAM 5101 (256B, batería) | set2: `0x3000–0x30FF` |
| `0xF400–0xF7FF` | **CHAR RAM** (vía CDP1869 `char_map`) | 1K ventana, RAM física 2K |
| `0xF800–0xFFFF` | **PAGE RAM** (vía CDP1869 `page_map`) | 2K ventana, RAM física 1K (mask 0x3FF) |

**I/O (`destryer_io_map`, instrucciones OUT/INP con N0–N2):**
| Puerto N | Dir | Función |
|---|---|---|
| `0x01` | INP | IN0 (controles/start/coin-via-PCB bit7). OUT 1 = nop (`destryer_out1_w`) |
| `0x02` | INP | IN1 (DIPs) |
| `0x03–0x07` | OUT | registros del CDP1869 (`out3..out7`) |

> Altair/Draco usan CDP1852 (latches I/O) en vez de puertos directos; Draco añade CPU de sonido
> COP402+AY8910. Se abordan después de Destroyer.

### Inputs Destroyer (activo-bajo salvo nota)
- **IN0**: b0 CARTUCHO, b1 START1, b2 START2, b3 JOY_RIGHT, b4 JOY_LEFT, b5 BUTTON1(fire),
  b7 = **PCB** (page color bit, activo-alto, leído por la CPU para sincronía de color).
- **IN1** (DIPs): b1:0 dificultad, b3:2 bonus, b5:4 vidas, b7:6 coinage.
- **EF lines** (leídas por branches del 1802): **EF1 = PRD invertido** (vblank), EF2 SERVICE,
  EF3 COIN2, EF4 COIN1 (todas activo-alto hacia la CPU).

---

## 3. CDP1869 — registros (OUT3–OUT7)  [verdad: `cdp1869.cpp`]

La CPU escribe con `OUT 3..7`. **Importante:** out3 usa el **dato** del bus; out4..out7 usan la
**dirección de memoria** (`get_memory_address()`, el valor en M(R(X)) tras el OUT) como payload de
16 bits. En HDL: out3 = byte de datos; out4..7 = los 16 bits de la dirección puesta por la CPU.

| Reg | Payload | Campos |
|---|---|---|
| **out3** | data[7:0] | `[2:0]` bkg(R/G/B fondo) · `[3]` CFC · `[4]` dispoff · `[6:5]` col · `[7]` freshorz |
| **out4** | addr[15:0] | `[3:0]` toneamp · `[6:4]` tonefreq · `[7]` toneoff · `[14:8]` tonediv |
| **out5** | addr[15:0] | `[0]` cmem · `[3]` line9 · `[5]` line16 · `[6]` dblpage · `[7]` fresvert · `[11:8]` wnamp · `[14:12]` wnfreq · `[15]` wnoff. **Además:** si cmem → `pma=addr`, si no `pma=0` |
| **out6** | addr[15:0] | `[10:0]` **pma** (page mem addr, mask 0x7FF) |
| **out7** | addr[15:0] | `[10:2]` **hma** (home addr, mask 0x7FC; bits 1:0 ignorados) |

Reset: todos a 0. `bkg=0, col=0, cfc=0, dispoff=0, line9=0, dblpage=0...`

---

## 4. Memorias de vídeo y formato de píxel  [verdad: `cdp1869.cpp` + `cidelsa_v.cpp`]

- **PAGE RAM**: 1K×8 (mask `0x3FF`; Draco 2K). Contiene el **código de carácter** por celda.
  Escaneada linealmente desde `hma`, wrap en `pmemsize = cols*rows (*2 si dblpage *2 si line16)`.
- **CHAR RAM**: 2K×8 (`0x800`). Dirección = `((code<<3) | (line & 0x07))`, con
  `code = (pma[10]? 0xFF : pageram[pma])`. → 256 códigos × 8 líneas. **Es RAM escribible**
  (la CPU carga el generador de caracteres al arrancar).
- **PCB RAM**: 2K×1 paralela a CHAR RAM. En cada escritura de CHAR se latchea el valor de **Q**
  (salida del 1802) como page-color-bit de esa celda. Se lee junto al patrón.

**Byte de CHAR RAM = `{ccb1, ccb0, p5,p4,p3,p2,p1,p0}`:**
- `p[5:0]` = patrón de 6 píxeles de esa línea (bit5 = píxel más a la izquierda).
- `ccb0 = bit6`, `ccb1 = bit7` = bits de control de color de la línea.
- `pcb` = de PCB RAM (latch de Q). → estos 3 bits + registros generan el color (§5).

Dirección de CPU a CHAR RAM (`char_ram_r/w`): `cma = offset & 0x0F` (línea), `pma = cmem? get_pma() : offset`.

---

## 5. Color → RGB  [verdad: `get_pen` + `get_rgb` + `cdp1869_palette`]

```
// índice de color de 3 bits según 'col' (out3[6:5])
col 0: r=ccb0, b=ccb1, g=pcb
col 1: r=ccb0, b=pcb,  g=ccb1
col 2,3: r=pcb, b=ccb0, g=ccb1
color3 = (r<<2)|(b<<1)|g                 // 0..7

// pen (índice en paleta de 72)
if (CFC==0) pen = color3                  // 0..7  (color-on-color)
else        pen = color3 + (bkg+1)*8      // 8..71 (tone-on-tone), bkg=out3[2:0]
```

**Paleta de 72 entradas** (precalculable como LUT en HDL):
```
get_rgb(c, l):  luma = (l&4?30:0)+(l&1?59:0)+(l&2?11:0); luma = luma*255/100
                R = (c&4)?luma:0 ; G = (c&1)?luma:0 ; B = (c&2)?luma:0
pen 0..7   : get_rgb(c=i, l=15)           // color-on-color, luma plena
pen 8..71  : i=8; for c in 0..7 for l in 0..7: pen(i++) = get_rgb(c, l)
             → pen(8 + c*8 + l) = get_rgb(c,l)
```
Equivalencia: en tone-on-tone, `pen = (bkg+1)*8 + color3` ⇒ usa `c=bkg`, `l=color3`.
Pesos de luminancia: **R 30% / G 59% / B 11%**.

---

## 6. Temporización de vídeo (PAL)  [verdad: `cdp1869.h`]

- `CH_WIDTH = 6`. Línea total = `60*6 = 360` dots. Total scanlines PAL = **312**.
- H (en dots 0..359): HBLANK_END=30 (`5*6`), HBLANK_START=324 (`54*6`); HSYNC 336..360 (`56..60 *6`).
  Visarea H del set_raw = `[HBLANK_END=30 .. HBLANK_START=324)`.
- Pantalla (display columnas): SCREEN_START_PAL=54 (`9*6`) .. SCREEN_END=300 (`50*6`).
- V (scanlines): VBLANK 304..(10 next), VSYNC 308..312, **DISPLAY 44..260** (216 vis),
  **PREDISPLAY 43..260**.
- **PRD**: ASSERT (=1) durante 43..260; CLEAR (=0) durante vblank (260..43 sig. frame).
  `INT = EF1 = ~PRD` ⇒ **INT/EF1 activos en vblank**. Esa es la interrupción de frame del juego.
- Dot clock Destroyer = **5.7143 MHz** (MAME `DESTRYER_CHR2`) con geometría PAL → Fv ≈ 50.9 Hz.
  Altair/Draco = **5.626 MHz** (`DOT_CLK_PAL`) → Fv ≈ 50.09 Hz. (BOM de Destroyer dice 5.626;
  discrepancia anotada, confirmar en placa — afecta sólo a Fv exacta, no a la geometría.)
- Doblado: `freshorz=0` ⇒ ancho ×2 (40→20 col efectivas dibujando doble); `fresvert=0` ⇒ alto ×2.
- Número de líneas por celda: `line16 && !dblpage → 16`, `!line9 → 9`, else `8` (`get_lines()`).
- ROT90 (mueble vertical): lo hace el scaler de MiSTer; el core saca raster normal.

---

## 7. Sonido (CDP1869)  [verdad: `sound_stream_update`]

- **Tono** (out4): `freq = (clk/2) / (512>>tonefreq) / (tonediv+1)`; onda cuadrada de amplitud
  `toneamp/15`; `toneoff` la silencia. (`clk` = dot clock del 1869.)
- **Ruido blanco** (out5[15:8]): **MAME NO lo implementa** (comentado). En FPGA = **LFSR** según
  datasheet RCA. Es la causa probable del flag *imperfect sound*. → bloque de sonido, fase tardía.
- Draco: además COP402 + AY-3-8910 (CPU de sonido aparte).

---

## 8. Plan de bloques (orden de implementación, estilo Galaxian)

| # | Bloque | RTL | Testbench | Depende |
|---|--------|-----|-----------|---------|
| 0 | **Timing de vídeo** (H/V, HS/VS, DISPLAY, PRD, ventana) | `rtl/vis_video_timing.v` | `sim/verilator` + `sim/tb_video_timing.v` | — |
| 1 | Registros out3–out7 (decode N0-2 + payload) | `rtl/vis_regs.v` | `sim/tb_regs.v` | — |
| 2 | PAGE/CHAR/PCB RAM + arbitraje CPU/scan (dual-port BRAM) | `rtl/vis_vram.v` | `sim/tb_vram.v` | 0,1 |
| 3 | Fetch+color: PAGE→code→CHAR→6px+ccb, paleta 72→RGB | `rtl/vis_pixel.v`, `rtl/vis_palette.v` | `sim/tb_pixel.v` | 0,1,2 |
| 4 | Integración VIS (`cdp1869`+`cdp1870`) | `rtl/vis_top.v` | `sim/tb_vis.v` (golden vs MAME) | 0-3 |
| 5 | CPU CDP1802 (adoptar core externo) + glue/decode | `rtl/cpu/...`, `rtl/cidelsa_machine.v` | `sim/tb_cpu.v` | — |
| 6 | Sistema Destroyer (ROM, NVRAM, inputs, EF, INT) | `rtl/cidelsa_top.v` | `sim/tb_system.v` | 4,5 |
| 7 | Sonido (tono + ruido LFSR) | `rtl/vis_sound.v` | `sim/tb_sound.v` | 1 |
| 8 | MiSTer wrapper + .mra + Quartus | `mister/`, `*.mra` | HW | 6,7 |

**Verificación (cadena Galaxian):** golden(Python/MAME) == MAME → sim == golden → hw == sim.
El oráculo pixel-exacto contra MAME es la herramienta más rentable (ver método Gaelco
"Golden Python").

---

## 9. Cuestiones abiertas (heredadas + nuevas)
- Dot clock Destroyer 5.7143 vs 5.626 (BOM): confirmar en placa; sólo afecta Fv.
- Ruido blanco: sin referencia en MAME → LFSR del datasheet RCA (pendiente).
- Draco: CPU sonido COP402 vs COP420; color CDP1870 vs CDP1876. Diferir a fase Draco.
- Reparto físico page-vs-char en 2114/2102: irrelevante para el HDL (lo modelamos como BRAM lógica).
</content>
