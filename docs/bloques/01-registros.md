# Bloque 1 — Registros de control del VIS (OUT3..OUT7)

**RTL:** `rtl/vis_regs.v` · **Harness:** `sim/verilator/tb_regs.cpp` ·
**Estado:** ✅ VALIDADO (22/22 checks, 2026-06-29)

## Qué hace
Latch de los registros de vídeo/sonido del CDP1869/1870. Fuente de verdad: `out3_w..out7_w`
(`reference/mame/cdp1869.cpp`) + el wrapper `cidelsa_state::cdp1869_w` (`cidelsa_v.cpp`).

## Truco clave del hardware (verificado en MAME)
La CPU escribe con `OUT N` (N=3..7). El payload del registro **no** es siempre el byte de datos:
- **OUT3** → payload = **byte de datos** (`data = M(R(X))`).
- **OUT4..7** → payload = **dirección del bus** (`addr = R(X)`, `get_memory_address()`), porque
  necesitan hasta 16 bits y no caben en el byte de datos.

Por eso `vis_regs` recibe **ambos**: `cpu_data[7:0]` y `cpu_addr[15:0]`. El glue del 1802
(bloque 5/6) generará `reg_wr` (1 pulso) con `reg_n=N` durante el ciclo OUT.

## Mapa de campos
| Reg | Payload | Campos |
|---|---|---|
| out3 | data | `bkg[2:0]` `cfc[3]` `dispoff[4]` `col[6:5]` `freshorz[7]` |
| out4 | addr | `toneamp[3:0]` `tonefreq[6:4]` `toneoff[7]` `tonediv[14:8]` |
| out5 | addr | `cmem[0]` `line9[3]` `line16[5]` `dblpage[6]` `fresvert[7]` `wnamp[11:8]` `wnfreq[14:12]` `wnoff[15]` · **además** `pma = cmem? addr[10:0] : 0` |
| out6 | addr | `pma = addr & 0x7FF` |
| out7 | addr | `hma = addr & 0x7FC` (bits 1:0 = 0) |

Reset: todos los campos a 0 (= `device_start`).

## Notas
- `pma` lo escriben out5 (condicional a cmem) y out6 (directo): gana el último OUT ejecutado.
- `hma` se almacena con bits [1:0]=0.
- Build/run: `./build.sh vis_regs tb_regs.cpp ../../rtl/vis_regs.v`.
</content>
