# Cidelsa "VIDEO SYSTEM-1" (EFO) — Listado de chips / BOM

Plataforma hardware común de **Destroyer, Altair, Altair II** (y, con variantes de sonido, **Draco**).
EFO la llama **"VIDEO SYSTEM-1"** (esquema proyectado 3‑2‑80 por F. Yago).

**Fuentes (definitivas):**
- **BOM por placas** del *manual de servicio de Destroyer* (`cidelsa/docs/destroyer_manual_servicio.pdf`):
  pág. 20 = PLACA M.P.U. · pág. 22 = PLACA V.I.S. · pág. 24 = FUENTE ALIMENTACIÓN · pág. 26 = ADJUST · pág. 28 = MONITOR.
- **Esquema eléctrico completo "VIDEO SYSTEM-1"** (pág. 42 del PDF): MPU + V.I.S. + Power Supply + Adjust a nivel de chip.
- **Esquema del MONITOR TV** (pág. 41) y **diagrama de cableado del sistema** (pág. 40).
- **Esquema de placa "VIDEO ALTAIR"** (`cidelsa/docs/altair_esquematicos.pdf`) — corrobora Altair.
- Cruzado con MAME (`efo/cidelsa.cpp`).

> El sistema se reparte en placas: **M.P.U.** (CPU+ROM+NVRAM), **V.I.S.** (vídeo+I/O), **FUENTE**,
> **ADJUST** (test/monedas/volumen), **MONITOR** y **R.G.B.** Conexión por conectores de poste
> (A1‑A6, B1‑B5, C1‑C8, D1‑D8, S1‑S8) — **no es JAMMA**. Las columnas del BOM "COPRESA/VIDEOCOLOR"
> son dos versiones de mueble.

---

## Placa M.P.U. (CPU)

| Nº | Componente | Qué es | Notas |
|---|---|---|---|
| 1 | **CDP1802** | CPU COSMAC 8 bits | "CPU 1802". XTAL 3.579 MHz |
| 2, 3 | **2× RAM 5101** (MM5101) | NVRAM CMOS 256×4 → 256 B | Respaldada por **batería 90 mAh Ni‑Cd** (marcador) |
| 4–7 | **ROM 2716** (2 KB) | EPROM de programa | Destroyer usa 4 (8 KB); **Altair/Altair II usan 6** (12 KB); Draco 8 (16 KB) |
| 8, 9 | **2× CDP1859** | Decodificador/latch de direcciones COSMAC | Sobre líneas A8/A9/A10 (en Altair hay 3) |
| — | Cristal cuarzo **3.579 MHz** | Oscilador | Reloj de la CPU |
| — | Diodo 1N4148, batería Ni‑Cd | — | Respaldo NVRAM |
| — | Conectores poste 6 vías (A1‑A6), hembra 30 vías | — | Bus al resto de placas |

> Glue de la M.P.U.: muy poca (3 resistencias 1K, 1×10K, 3×100K, 1×10M; condensadores 0.1µF/10µF/cerámicos).

---

## Placa V.I.S. (vídeo + sonido + I/O) — la pieza a implementar

| Nº | Componente | Qué es | Notas |
|---|---|---|---|
| 10 | **CDP1869** | VIS: generador de direcciones (page/char RAM) **+ sonido** (tono+ruido) | XTAL **5.626 MHz** |
| 16 | **CDP1870** | VIS: generador de vídeo **en color** | Salidas DISPLAY/PCB/CCB/COB/SYNC → placa R.G.B. (no es 1876) |
| 11, 12, 19, 20 | **4× RAM 2114** (1K×4) | SRAM | PAGE RAM y CHAR RAM |
| 15, 21 | **2× RAM 2102** (1K×1) | SRAM | Complemento de page/char RAM |
| 17, 18 | **2× CDP1856** | Buffer de bus de datos COSMAC (4 bits) | (No son SRAM; corrige la lectura previa del esquema) |
| 22, 23 | **2× CDP1852** (INPUT) | Puerto de entrada paralelo | Mandos / monedas / DIP |
| 24 | **CDP1852** (OUTPUT) | Puerto de salida paralelo | Salidas (contadores, etc.) |
| 25 | **CD4025** | Triple puerta NOR de 3 entradas (CMOS) | Lógica de pegamento |
| — | Cristal cuarzo **5.626 MHz** | Oscilador | Reloj de píxel del CDP1869/1870 |
| — | Redes de resistencias 8×10K, 2× 16×100K; 8×1K | Pull‑ups | Líneas de entrada / DIP |
| — | Conectores B1‑B5, C1‑C8, D1‑D8, S1‑S8, hembra 30 vías, 4 vías | — | Bus + mandos + salida vídeo |

> **Memoria de vídeo total ≈ 6× 2114 + 2× 2102.** Reparto exacto page‑vs‑char no rotulado, pero el
> esquema agrupa **PAGE RAM** (11,12) y **CHAR RAM** (13/14→ son 2114, 19,20,15,21).
> Para Altair, el set `altair` añade un 4º CDP1852 (entradas extra: up/down + 2º botón).

---

## Placa FUENTE DE ALIMENTACIÓN

| Nº / Desig | Componente | Qué es |
|---|---|---|
| 27 | **7805C** (323K) | Regulador +5 V |
| 26 | **LM383** | Amplificador de audio (al altavoz) |
| 28 | **CD4020B** | Contador binario CMOS (timing/divisor) |
| T3, T4 | SC148C / SC158C | Transistores |
| D5 | Zener 6.2 V; D6/D7 BY251; D4 1N4148 | Diodos |
| — | Transformador, fusibles 3 A ×2, electrolíticos 4700/2200 µF | Fuente |

---

## Placa ADJUST (ajustes / monedas)

| Desig | Componente | Qué es |
|---|---|---|
| TI1–TI3 | **3× tiristor RCA C‑106‑F** | Disparo (contadores de moneda / lámparas) |
| T1, T2 | BC338 | Transistores |
| D1,D2 1N4148; D3 1N4001 | — | Diodos |
| — | **Mini‑interruptor DIP BT‑8** | DIP de configuración (dificultad/vidas/bonus/coinage) |
| — | Potenciómetro **VOLUMEN 5K**, pulsador **TEST** | Ajustes |
| J1,J2,J3 | Conectores 12 / 11 / 4 vías | — |

---

## Relojes / osciladores (resumen)

| Cristal | Frecuencia | Placa | Reloj de |
|---|---|---|---|
| Cuarzo | **3.579 MHz** | M.P.U. | CPU CDP1802 |
| Cuarzo | **5.626 MHz** | V.I.S. | CDP1869 / CDP1870 (píxel) |

> En MAME, Destroyer figura con vídeo @ **5.7143 MHz** (refresco 50.875 Hz); el BOM del manual indica
> **5.626 MHz** (como Altair). Posible revisión o manual genérico de plataforma. A confirmar.

---

## Cadena de sonido por juego

- **Destroyer / Altair / Altair II:** el sonido lo genera el **CDP1869** (tono + ruido) → **LM383** → altavoz.
  No hay CPU de sonido. (El *imperfect sound* de MAME cuadra con el ruido blanco no implementado.)
- **Draco:** añade **COP402 + AY‑3‑8910A** (2.0122 MHz) en su placa; el resto de la arquitectura es igual.

---

## Mapa del manual (qué hay en cada página del PDF)

| Pág. PDF | Contenido | Valor para FPGA |
|---|---|---|
| 22 | BOM **PLACA M.P.U.** | Chips CPU/ROM/NVRAM (defin.) |
| 23 | Layout (serigrafía) V.I.S. | Posiciones físicas 10–25 |
| 24 | BOM **PLACA V.I.S.** | **Chips de vídeo/I/O (defin.)** |
| 25 | Layout fuente | — |
| 26 | BOM **FUENTE** | Audio/regulador |
| 27 | Layout adjust | — |
| 28 | BOM **ADJUST** | DIP/monedas |
| 40 | **Diagrama de cableado del sistema** | Interconexión de placas + control panel + monedas |
| 41 | **Esquema MONITOR TV** | Chasis monitor (TDA1170/2591/2530/4600) — solo monitor |
| 42 | **Esquema eléctrico "VIDEO SYSTEM-1"** | **Esquema completo a nivel de chip (oro)** |

---

## Resumen para FPGA

Listado de ICs "lógicos" de la placa de juego (M.P.U. + V.I.S.), **todo confirmado por BOM + esquema**:

```
CPU:        1× CDP1802            (3.579 MHz)
Decode:     2× CDP1859            (address decode/latch)
ROM:        4–8× 2716             (8/12/16 KB según juego)
NVRAM:      2× 5101 (+bat NiCd)   (256 B, marcador)
Vídeo:      1× CDP1869 + 1× CDP1870   (5.626 MHz)
Video RAM:  ~6× 2114 + 2× 2102    (page RAM + char RAM)
Bus buf:    2× CDP1856
I/O:        3× CDP1852 (Altair 4) (2/3 IN + 1 OUT)
Glue:       1× CD4025 (NOR), 1× CD4020B (en fuente)
Audio:      CDP1869 → LM383       (Draco: + COP402 + AY-3-8910)
```

Es un diseño COSMAC "de catálogo": casi todo son chips RCA de la familia 18xx, **mínima lógica TTL**.
La única pieza sin core FPGA existente sigue siendo el **CDP1869/1870** (ver `referencia_cidelsa_mame.md` §6).
