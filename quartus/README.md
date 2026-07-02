# Build Quartus — Cidelsa "Destroyer" (DE10-Nano / Cyclone V)

Proyecto de **síntesis del core** Cidelsa Destroyer para Quartus Prime 17.0 Lite,
device **5CSEBA6U23I7** (DE10-Nano). Su objetivo es comprobar que el RTL **sintetiza,
cabe e infiere BRAM** correctamente con los relojes reales de la placa.

## Qué incluye
- `cidelsa_destroyer_top.v` — top de síntesis: genera los clock-enables `ce_cpu`
  (3.579 MHz) y `ce_pix` (5.626 MHz) **— relojes REALES confirmados en el manual de
  servicio de Destroyer** — desde `FPGA_CLK1_50` por acumuladores (frecuencia media
  exacta), instancia `cidelsa_machine` y saca vídeo/audio a pines.
- `cidelsa_destroyer.qpf/.qsf/.sdc` — proyecto, ajustes y timing (reloj 50 MHz).
- `destryer_prog.hex` — ROM de programa (8 KB), cargada por `$readmemh` en síntesis.

## Compilar
```sh
cd quartus
# Análisis & Síntesis (sintetiza, infiere RAM/ROM, uso de recursos):
quartus_map.exe cidelsa_destroyer -c cidelsa_destroyer
# Fitter (place&route, timing):
quartus_fit.exe cidelsa_destroyer -c cidelsa_destroyer
quartus_sta.exe cidelsa_destroyer -c cidelsa_destroyer
# o todo de una:
quartus_sh.exe --flow compile cidelsa_destroyer
```

## Resultado de compilación (Quartus 17.0 Lite, DE10-Nano)
> ⚠️ **A RE-MEDIR.** El primer build (A&S+Fitter OK, 45% ALMs, Fmax 34 MHz, timing
> cerrado a 30 MHz) se hizo con la **ROM registrada**, que luego se comprobó que
> **rompe el CPU** (el CDP1802 lee memoria combinacional, no tolera 1 clk de latencia).
> El RTL actual usa memoria **ASÍNCRONA** del bus de CPU con `ramstyle="MLAB"` (LUTRAM
> async en Cyclone V). Hay que **re-compilar** para obtener recursos/timing reales y
> confirmar que sintetiza sin atasco. El refactor de **vídeo** (BRAM M10K registrada)
> NO cambia y sigue validado (replay 0.00%).

- El core es **enable-gated** (CPU 3.579 / vídeo 5.626 MHz por `ce`) → `clk_sys` = 30 MHz.
  El `.sdc` está a 30 MHz (period 33.333 ns). En HW, un **PLL** genera 30 MHz desde
  `FPGA_CLK1_50` (el top de síntesis usa `FPGA_CLK1_50` directo como placeholder).

## Notas de arquitectura (síntesis)
- **Vídeo** (`vis_video` + `vis_vram`): refactor SINTETIZABLE ya validado contra el
  golden (replay = MAME 0.00%). Sin divisores por píxel (contadores de celda) y con
  BRAM **registrada** (copia `*_v` → M10K) + pipeline de 2 dots. La copia de CPU es
  LUTRAM async (lectura combinacional del bus 1802) — Cyclone V lo soporta (MLAB).
- **CPU/ROM/NVRAM**: el bus del 1802 es de lectura asíncrona (ROM 8 KB, NVRAM 256 B);
  infiere LUTROM/LUTRAM. Cabe de sobra en la Cyclone V del DE10-Nano.
- **Relojes**: aquí se derivan del 50 MHz por `ce`. En el wrapper MiSTer final se usará
  un PLL del framework (mismos `ce`).

## Camino al core MiSTer completo (pendiente)
Este proyecto es el **paso de validación de síntesis**. Para el core MiSTer jugable falta
el andamiaje del framework (no incluido aquí):
1. Clonar el **Template_MiSTer** (`MiSTer-devel/Template_MiSTer`) → aporta `sys/`
   (hps_io, sys_top, video scaler, .sdc, build).
2. Escribir el wrapper `Cidelsa.sv` (módulo `emu`) con el port-list del template:
   - PLL → `clk_sys` + `ce_cpu`/`ce_pix` (3.579 / 5.626 MHz).
   - `cidelsa_machine` → `VGA_R/G/B`, `VGA_HS/VS/DE`, `CE_PIXEL`; `AUDIO_L/R`.
   - `hps_io`: joystick → `in0`, DIPs → `in1`, carga de ROM por HPS a la `rom`.
   - ROT90 (mueble vertical) lo hace el scaler MiSTer (`status`/`VIDEO_ARX/ARY`).
3. `.mra` para empaquetar la ROM (`destryer` de MAME 0.288).

Referencia de andamiaje: `JasonA-dev/RCAStudioII_Mister` (ya trae 1802 + template).
