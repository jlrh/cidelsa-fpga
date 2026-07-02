# CDP1869 + CDP1870 (VIS) — Mapa de señales para el HDL de vídeo

Punto de partida para implementar el vídeo de la plataforma Cidelsa "VIDEO SYSTEM-1" en FPGA.
Combina dos fuentes:
- **Topología de placa** (qué conecta con qué): esquema *VIDEO SYSTEM-1* y BOM del manual de Destroyer
  (`cidelsa/docs/`), y el esquema de Altair.
- **Función de cada pin y mapa de registros** (autoritativo): device de MAME
  `src/devices/sound/cdp1869.{h,cpp}` (RCA CDP1869/1870/1876 VIS) + datasheet RCA VIS.

> Reparto de funciones: **CDP1869** = direccionamiento de memorias (página y carácter) **+ sonido**;
> **CDP1870** = generación de vídeo y color (sync + bits de color). En Cidelsa el color se convierte a
> RGB analógico en la **placa R.G.B.** externa (red de transistores) → monitor.

---

## 0. Diagrama de bloques (clk domains incluidos)

```
   XTAL 3.579 MHz                          XTAL 5.626 MHz (PAL) / 5.670 (NTSC)
        │                                        │
   ┌────▼────┐   A0-A7 (MA mux)   ┌──────────────▼───────────────┐
   │ CDP1802 │◄────TPA/TPB───────►│           CDP1869            │
   │  (CPU)  │   _MRD/_MWR        │  (address gen + sound)        │
   │ IC1     │   N0-N2 (reg sel)  │  IC10                         │
   └────┬────┘◄──_INT (predisp)──┤  PMA0-10 ─► PAGE RAM (IC11,12)│
        │ B0-B7 (data, vía 1856) │  MA0/8..7/15, CMA0-3 ─► CHAR  │
        │                        │  SOUND ─► LM383 ─► altavoz    │
        │                        └───┬───────────────┬───────────┘
   ROM 2716 (IC4-7)                  │ PMSEL/PMWR     │ CMSEL/CMWR, TPB
   RAM 5101 ×2 (NVRAM)          PAGE RAM           CHAR RAM (IC13,14,19,20=2114;
   CDP1859 ×2 (decode)          IC11,12 (2114)               IC15,21=2102)
                                     │                       │ CDB0-5 / BUS0-7
                                     └──────────┬────────────┘
                                          ┌─────▼─────┐  CCB0,CCB1,PCB
                                          │  CDP1870  │  _HSYNC,_COMPSYNC
                                          │  IC16     │  LUM/CHROM (1870)
                                          └─────┬─────┘
                                       placa R.G.B. (DAC transistores)
                                                │  R · G · B · SYNC
                                            MONITOR
```

**Dos dominios de reloj independientes:** la CPU va a **3.579 MHz** (cristal propio en la M.P.U.);
el vídeo (1869/1870 + RAM) va a **5.626 MHz** (cristal en la V.I.S.). NO se cumple CPUCLK=DOT/2 aquí
(el pin CPUCLK del 1870 no clockea la CPU). La sincronía CPU↔vídeo se hace por **TPA/TPB** (la CPU las
genera y el 1869 las usa para multiplexar la dirección) y por la **interrupción de _PREDISPLAY/_DISPLAY**
del 1870→1802.

---

## 1. CDP1869 — pinout (40 pines, verbatim del device MAME)

```
 TPA   1 | 40 Vdd            TPA,TPB    : timing pulses de la CPU (entrada)
 TPB   2 | 39 PMSEL          _MRD,_MWR  : lectura/escritura de memoria
_MRD   3 | 38 _PMWR          MA0/8..7/15: bus de dirección multiplexado (16→8)
_MWR   4 | 37 CMSEL          N0,N1,N2   : selección de registro/operación (I/O)
MA0/8  5 | 36 _CMWR          PMA0..PMA10: dirección de PAGE memory (11 bits)
MA1/9  6 | 35 PMA0           CMA0..CMA3 : dirección de CHAR memory (4 bits = línea)
MA2/10 7 | 34 PMA1           PMSEL/_PMWR: select/write de PAGE RAM
MA3/11 8 | 33 PMA2           CMSEL/_CMWR: select/write de CHAR RAM
MA4/12 9 | 32 PMA3           _HSYNC     : sync horizontal
MA5/13 10| 31 PMA4           _DISPLAY   : display activo
MA6/14 11| 30 PMA5           _ADDRSTB   : address strobe
MA7/15 12| 29 PMA6           SOUND      : salida de audio (tono+ruido)
 N0   13 | 28 PMA7           _N=3       : activo cuando N2:N0 = 3
 N1   14 | 27 PMA8
 N2   15 | 26 PMA9
_HSYNC 16| 25 CMA3/PMA10     (pin 25 = CMA3 o PMA10 según modo)
_DISPLAY 17|24 CMA2
_ADDRSTB 18|23 CMA1
SOUND 19 | 22 CMA0
 Vss  20 | 21 _N=3
```

---

## 2. CDP1870 — pinout (40 pines; CDP1876 = igual con salidas RGB)

```
_PREDISPLAY 1 | 40 Vdd          BUS0..BUS7 : bus de datos de color (a CHAR RAM)
_DISPLAY    2 | 39 PAL/_NTSC    CDB0..CDB5 : color data bits
 PCB        3 | 38 CPUCLK       CCB0,CCB1  : color control bits (salida)
 CCB1       4 | 37 XTAL(DOT)    PCB        : point/page color bit
 BUS7       5 | 36 _XTAL(DOT)   _HSYNC     : sync H
 CCB0       6 | 35 _ADDRSTB     _COMPSYNC  : sync compuesto
 BUS6       7 | 34 _MRD         BURST      : ráfaga de color
 CDB5       8 | 33 TPB          PAL/_NTSC  : selección de estándar (auto-detect)
 BUS5       9 | 32 CMSEL        XTAL(DOT)  : reloj de píxel 5.626/5.670 MHz
 CDB4      10 | 31 BURST        XTAL(CHROM): subportadora color 8.867/7.159 MHz
 BUS4      11 | 30 _HSYNC       CDP1870 pin 28/27/26 = LUM / PAL-CHROM / NTSC-CHROM
 CDB3      12 | 29 _COMPSYNC    CDP1876 pin 28/27/26 = RED / BLUE / GREEN
 BUS3      13 | 28 LUM (o RED)
 CDB2      14 | 27 PAL-CHROM (o BLUE)
 BUS2      15 | 26 NTSC-CHROM (o GREEN)
 CDB1      16 | 25 _XTAL(CHROM)
 CDB0      18 | 23 _EMS         _EMS,_EVS  : event marker / vertical sync flags
 BUS0      19 | 22 _EVS
 Vss       20 | 21 _N=3
```

> **Cidelsa monta el CDP1870** (BOM nº 16). Sus salidas digitales de color **CCB0, CCB1, PCB** (+ la
> luminancia) van a la **placa R.G.B.** que las convierte a R/G/B analógico. Para el FPGA NO hace falta
> replicar LUM/CHROM: se genera directamente R/G/B a partir de CCB0/CCB1/PCB (ver §5).

---

## 3. Interfaz CPU ↔ 1869 (cómo se escriben los registros)

La CPU CDP1802 accede a los registros del 1869/1870 con instrucciones **OUT 3..7** (las líneas
**N0‑N2** llevan el número de registro 3..7; el dato sale por el bus). El 1869 multiplexa la dirección
del 1802 (alto/bajo) con **TPA** (latch del byte alto) y la entrega como **MA0/8..MA7/15**.

| Línea | Origen | Función en el HDL |
|---|---|---|
| `TPA` | CPU | Latch del byte alto de dirección (A8‑A15) |
| `TPB` | CPU | Strobe de datos / fin de ciclo de máquina |
| `_MRD/_MWR` | CPU | Sentido del acceso a memoria |
| `N0,N1,N2` | CPU | Nº de registro/operación (3..7); `_N=3` marca N=3 |
| `MA0/8..7/15` | CPU↔1869 | Bus de dirección multiplexado (8 líneas, dos fases) |
| `B0‑B7` | bus datos | Dato CPU↔memoria/registros (en placa pasa por **CDP1856**, IC17/18) |
| `_INT` ← `_PREDISPLAY` | 1870→CPU | Interrupción de vídeo (sincroniza el juego con el frame) |

---

## 4. Mapa de registros (out3‑out7) — bits exactos (MAME)

| Reg | Dir (N) | Función | Bits |
|---|---|---|---|
| **out3** | 3 | Display y color | `[2:0]` bkg (R/G/B fondo) · `[3]` **CFC** (modo paleta) · `[4]` dispoff · `[6:5]` col (modo color) · `[7]` **freshorz** |
| **out4** | 4 | **Tono** (audio) | `[3:0]` toneamp · `[6:4]` tonefreq (octava) · `[7]` toneoff · `[14:8]` tonediv (divisor) |
| **out5** | 5 | Formato vídeo + **ruido** | `[0]` cmem · `[3]` line9 · `[5]` line16 · `[6]` dblpage · `[7]` **fresvert** · `[11:8]` wnamp · `[14:12]` wnfreq · `[15]` wnoff |
| **out6** | 6 | Dirección PAGE memory | `[10:0]` pma (11 bits, máscara 0x7FF) |
| **out7** | 7 | Dirección CHAR/HMA | `[10:2]` hma (máscara 0x7FC; bits 1:0 ignorados) |

- **Resolución:** `freshorz`/`fresvert` = 0 ⇒ se **duplican** píxeles/líneas (40→20 col, etc.).
- **dispoff** apaga el display. **CFC** elige paleta color‑on‑color (0) vs tono‑on‑tono (1).
- **Tono:** `freq = (clk/2) / (512 >> tonefreq) / (tonediv+1)`; `tonefreq`∈[0..7], `tonediv`∈[0..127].
- **Ruido (out5[15:8]):** ⚠️ **MAME lo deja sin implementar** → para el FPGA es un **LFSR** (ver datasheet).

---

## 5. Generación de color / RGB (lo que va al output del core)

Entradas por píxel: `ccb0` (= BUS7), `ccb1` (= BUS6), `pcb` (point/page color bit), y el registro
`col` (out3[6:5]) + `CFC` (out3[3]) + `bkg` (out3[2:0]).

```
// 1) índice de color de 3 bits según el modo 'col'
col mode 0: r=ccb0, b=ccb1, g=pcb
col mode 1: r=ccb0, b=pcb,  g=ccb1
col mode 2/3: r=pcb, b=ccb0, g=ccb1
color3 = (r<<2) | (b<<1) | g            // 0..7

// 2) índice de paleta
if (CFC==0) pen = color3                       // 8 entradas (color-on-color)
else        pen = color3 + (bkg+1)*8           // 64 entradas (tono-on-tono)

// 3) paleta de 72 entradas (8 + 64). Cada entrada → RGB por pesos de luminancia:
//    l = índice de luminancia (3 bits)
luma = ((l&4)?30:0) + ((l&1)?59:0) + ((l&2)?11:0);   // pesos R30/G59/B11 (%)
component = luma * 255 / 100;
```

- **PALETTE_LENGTH = 8 + 64 = 72.** Pesos: `R=30 %, G=59 %, B=11 %`.
- En la placa real estos bits digitales pasan por la **placa R.G.B.** (DAC de transistores) → R/G/B
  analógico + SYNC al monitor. En FPGA: implementar la paleta de 72 y sacar RGB directo (p. ej. al
  scaler/HDMI de MiSTer).

---

## 6. Memorias de vídeo (direccionamiento + chips físicos)

| Memoria | Contenido | Dirección | Chips (BOM) | Notas |
|---|---|---|---|---|
| **PAGE RAM** | Código de carácter por celda (40×24) | **PMA0‑PMA10** (out6) | **2× 2114** (IC11,12) → 1K×8 | `dblpage`=0 ⇒ 10 bits (0x3FF); =1 ⇒ 11 bits |
| **CHAR RAM** | Patrón de bits + color del carácter | {código (de PAGE RAM)} + **CMA0‑CMA3** (línea 0‑15) | **4× 2114 + 2× 2102** (IC13,14,19,20,15,21) | `dblpage`=1 ⇒ CMA 3 bits (líneas 0‑7) |

- **CHAR RAM es RAM, no ROM:** la CPU carga los patrones de carácter al arrancar (generador de
  caracteres por software). Importante para el HDL: el char generator es escribible.
- Selección/escritura: `PMSEL`/`_PMWR` (página), `CMSEL`/`_CMWR` (carácter). El dato de carácter sale
  por `CDB0‑5`/`BUS0‑7` hacia el 1870.
- CMA: `cma = offset & 0x0F` (línea dentro de la celda; &0x07 si dblpage).

---

## 7. Temporización de vídeo (constantes MAME)

| Parámetro | NTSC | PAL |
|---|---|---|
| Dot clock | 5.670 MHz | **5.626 MHz** |
| Color clock | 7.159 MHz | 8.867 MHz |
| Líneas totales | 262 | **312** |
| Rango display (líneas) | 36–228 | 44–260 |
| Líneas visibles | 192 | **216** |
| Ancho de celda | `CH_WIDTH = 6` px | igual |
| Columnas | 40 (full) / 20 (half) | igual |
| Filas | 24 (NTSC full) | 25 (PAL full) / 12 (half) |
| HSYNC | 56–60 × 6 | igual |
| HBLANK | 54×6 … 5×6 | igual |
| Inicio/fin pantalla (col) | 10×6 … 50×6 | igual |
| Ancho total línea | 60 × 6 = **360 dots** | igual |

- **Cidelsa va a PAL** (5.626 MHz): Fh = 5.626e6 / 360 ≈ **15.63 kHz**; Fv ≈ 15.63k/312 ≈ **50.09 Hz**
  (coincide con el refresco de Altair/Draco en MAME). Pantalla **rotada 90°** (vertical) en el mueble.
- Destroyer en MAME usa 5.7143 MHz (NTSC-like, 50.875 Hz); el BOM dice 5.626. A confirmar en placa.
- Celda 6×8 (NTSC) / 6×9 (PAL) según `line9`/`line16`. Con `freshorz/fresvert`=0 se duplica.

---

## 8. Plan para el HDL del vídeo (orden sugerido)

1. **Generador de timing** (dominio 5.626 MHz): contadores H (0..359, CH_WIDTH=6) y V (0..311),
   genera `_HSYNC`, `_COMPSYNC`, `_DISPLAY`, `_PREDISPLAY`, ventana visible (10..50 col × 44..260 lín).
2. **Interfaz de registros** (out3‑out7): decodifica N0‑N2 + OUT del 1802; guarda bkg/col/CFC/dispoff/
   freshorz/fresvert/line9/line16/dblpage + pma/hma + tono/ruido.
3. **Fetch de página**: por cada celda, PMA → PAGE RAM → código de carácter.
4. **Fetch de carácter**: {código, línea CMA} → CHAR RAM → patrón 6 px + bits de color (ccb0/ccb1/pcb).
5. **Color**: aplicar §5 → índice de paleta → RGB (72 entradas, pesos 30/59/11).
6. **Doblado** de píxel/línea según freshorz/fresvert; **rotación 90°** (puede hacerla el scaler MiSTer).
7. **Sonido** (puede ir aparte): tono (out4) + ruido LFSR (out5) → mezcla → DAC.
8. **Sincronía con CPU**: `_PREDISPLAY`→`_INT` del 1802; multiplexado de dirección con TPA/TPB para los
   accesos de CPU a PAGE/CHAR RAM (arbitraje con el refresco de vídeo).

---

### Referencias
- Device MAME (verdad de referencia de registros/paleta/timing): `src/devices/sound/cdp1869.{h,cpp}`
  (github.com/mamedev/mame). Driver de placa: `src/mame/efo/cidelsa.cpp`.
- Datasheet RCA "CDP1869/1870/1876 VIS" (bitsavers / cosmacelf) — **única fuente del ruido blanco**.
- Esquema *VIDEO SYSTEM-1* y BOM: `cidelsa/docs/` (este repo). Inventario de chips: `cidelsa/altair_chips.md`.
- Visión general de la plataforma: `referencia_cidelsa_mame.md`.
