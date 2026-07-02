# Bloque 7 — Sonido del CDP1869 (tono + ruido)

**RTL:** `rtl/vis_sound.v` · **Harness:** `sim/verilator/tb_sound.cpp` ·
**Estado:** ✅ VALIDADO (tono = fórmula MAME exacta; ruido LFSR funcional, 2026-06-30)

## Qué hace
Genera el audio del CDP1869: **tono** (registro out4) + **ruido blanco** (out5). Corre con `ce_pix`
(dot clock). Registros desde `vis_regs`. Salida: muestra con signo `[15:0]`.

## Tono (out4) — verdad: `sound_stream_update` (cdp1869.cpp)
- `freq = (dot/2) / (512>>tonefreq) / (tonediv+1) = dot / (2·D)`, con `D = (512>>tonefreq)·(tonediv+1)`.
- Onda cuadrada bipolar de amplitud `toneamp/15`; `toneoff` la silencia.
- Implementación: contador a `ce_pix` que conmuta cada **D** ciclos de dot (semiperiodo).
- `tonefreq`∈0..7 → base 512..4; `tonediv`∈0..127 → ×1..128; D∈[4, 65536].

## Ruido (out5) — LFSR (MAME NO lo implementa → datasheet RCA)
- LFSR de 17 bits maximal (`x^17 + x^14 + 1`), clockeado cada `(4096>>wnfreq)` ciclos de dot.
- Salida 1 bit, amplitud `wnamp/15`; `wnoff` lo silencia.

## Mezcla
`audio = (tono ± toneamp + ruido ± wnamp) << 9` → ~±15360 (16-bit con signo). La escala fina /
volumen final la hace el wrapper MiSTer (en placa: LM383 → altavoz).

## Validación
`tb_sound.cpp`: mide el semiperiodo del tono = **976 ciclos de dot** para tonefreq=5/tonediv=60
(= D exacto), y comprueba que el LFSR del ruido varía (no se atasca). **TODO OK.** Cableado en
`cidelsa_machine` (el sistema vivo sigue dando 200 OUTs == MAME).

## Notas
- Draco añade además COP402 + AY-3-8910 (CPU de sonido aparte) — fase Draco.
- El ruido es la causa probable del flag *imperfect sound* de MAME en Destroyer/Altair.
</content>
