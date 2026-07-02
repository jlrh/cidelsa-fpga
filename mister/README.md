# Destroyer (Cidelsa, 1980) — core MiSTer

Core MiSTer del arcade **Destroyer** (EFO/Cidelsa, 1980): CPU **CDP1802** + VIS
**CDP1869/1870**, todo en BRAM (sin SDRAM). Vídeo pixel-perfect validado contra MAME
(replay 0.00%) y CPU validada (2635 OUTs idénticas a MAME).

> **Filosofía de 3 cores separados.** Cada juego del VIDEO SYSTEM-1 es un core MiSTer
> independiente (una "placa"): **Destroyer** (este), **Altair** y **Draco**. Comparten el
> RTL común en `../rtl/` (CPU 1802, `vis_*`) pero cada uno es su propio proyecto/`.rbf`.
> Altair reutiliza `cidelsa_machine` (mismo mapa, otra ROM y reloj de CPU); Draco usa
> `draco_machine` (mapa distinto + sonido COP402/AY).

## Estructura
- `Destroyer.sv` — módulo `emu` (top del framework). Instancia `../rtl/cidelsa_machine.v`,
  cablea hps_io + arcade_video + audio + carga de ROM por ioctl.
- `pll.v` / `pll.qip` — PLL **50→30 MHz** (`clk_sys`). El core es enable-gated:
  `ce_cpu`=3.579 MHz, `ce_pix`=5.626 MHz (relojes REALES del manual de servicio).
  Fmax del core ≈ 34 MHz → 30 MHz cierra timing (+3.9 ns).
- `Destroyer.qsf/.sdc/.qpf` + `files.qip` — proyecto Quartus (top `sys_top`, DE10-Nano
  `5CSEBA6U23I7`, revisión **Destroyer**). `sys/` = framework Template_MiSTer
  (**NO incluido en el repo**: cópialo aquí desde
  https://github.com/MiSTer-devel/Template_MiSTer antes de compilar).
- `build_id.v` — stub (en el flujo completo lo regenera `sys/build_id.tcl`).

El **`.mra`** (empaquetado de `destryer.zip`, 4×2KB → índice 0, `<rbf>destroyer</rbf>`) y el
`.rbf` publicado están en [`../releases/`](../releases/).

## Compilar (genera el .rbf)
```sh
cd mister
quartus_sh --flow compile Destroyer       # ~1 h en Lite; produce output_files/Destroyer.rbf
```
> Quartus **17.0** (Standard o Lite). El `.qsf` está basado en el de un core probado
> (Gaelco WRally) para esta misma placa.

## Desplegar en MiSTer
1. Copiar `../releases/destroyer_YYYYMMDD.rbf` → `/media/fat/_Arcade/cores/`.
2. Copiar `../releases/Destroyer (Cidelsa, 1980).mra` → `/media/fat/_Arcade/`.

   (o simplemente `python deploy_destroyer.py`, que ya aplica estos nombres)
3. Poner `destryer.zip` (MAME) en `/media/fat/games/mame/`.
4. El `.mra` carga la ROM al core por HPS (ioctl índice 0).

## Entradas (Destroyer)
- Joystick: **Izquierda/Derecha** = mover; **Fire** = disparar.
- **Start 1P/2P**, **Coin**. DIPs (Difficulty/Bonus/Lives/Coinage) por OSD o `.mra`.

## Rotación de pantalla (vertical/horizontal)
Destroyer es de **mueble vertical**. Implementada vía `screen_rotate` (en `sys/arcade_video.v`)
+ framebuffer en DDRAM (`MISTER_FB=1` en el `.qsf`):
- OSD **Orientation**: `Vertical` (rota 90º, orientación correcta) / `Horizontal` (raster nativo).
- OSD **Flip 180**: gira 180º (sentido de rotación en vertical, flip del framebuffer en horizontal).
- `VIDEO_ARX/ARY` se ajustan a 3:4 (vertical) / 4:3 (horizontal).
- Todo en un solo dominio de reloj (clk_sys=30 MHz); si el DDR diera problemas de ancho de
  banda en HW, añadir un `clk_video` más rápido (2ª salida del PLL) con su CDC.

## Nota sobre `vis_vram` (compartido con Draco)
La PAGE RAM de la CPU es ahora de 2KB (lectura/escritura `[10:0]`) para soportar Draco.
Destroyer solo usa 1KB (bit10=0); **verificado que sigue == 2635 OUTs** tras el cambio.

## Pendiente / notas
- **Optimización**: las copias async de CPU de `vis_vram` (char/page) se implementan
  como ~24K FFs; registrarlas (como la ROM) las bajaría a BRAM y subiría el Fmax.
- Afinar mapeo de inputs/DIPs y la mezcla/escala de audio en HW.
