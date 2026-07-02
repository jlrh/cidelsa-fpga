# HANDOFF — Destroyer en MiSTer (2026-07-01)

Estado de la depuración del bug de HW de Destroyer y cómo continuar.
Memoria relacionada: `hw-bug-timing-attract-scramble.md`, `quartus-build-destroyer-estado.md`.

---

## ESTADO (actualizado 2026-07-02)

- ✅ **BUILD FINAL HECHO con TODOS los fixes** — DIP (`in1=sw[0]=0xd6`), `ce_cpu` reloj/8, CONF_STR `"DIP;"`
  **+ fix del CPU SHRC/SHLC (0x76/0x7E)** que arregla el attract scrambled. `mister/output_files/Destroyer.rbf`
  regenerado (2.594.788 bytes, 2026-07-02 08:34). Quartus: *Full Compilation was successful. 0 errors, 94 warnings*.
  files.qip apunta a `../rtl/cpu/cdp1802_jl.v` (el fichero corregido) → el fix ESTÁ en el bitstream.
- ⏳ **DEPLOY + TEST PENDIENTES** (no había MiSTer disponible). Este `.rbf` debería arreglar EL "muere en 2s"
  (DIP) Y el attract scrambled (CPU). Script listo:
  `mister/deploy_destroyer.py` → sube `.rbf`+`.mra` a .123/.88 por SFTP, verifica tamaño y `sync`.
  Para desplegar cuando la placa esté disponible:  `python mister/deploy_destroyer.py`
  (comprueba que existe `output_files/Destroyer.rbf` antes de subir; si el build es viejo, rebuild — ver Paso 1).
- Tras deploy: cargar core `_Arcade → Destroyer (Cidelsa)`, reset, mirar attract (¿legible?, ¿no muere en 2 s?),
  screenshot vía `echo "screenshot" > /dev/MiSTer_cmd` y bajar PNG de `/media/fat/screenshots/destryer/`.

---

## TL;DR

- **Destroyer YA corre en HW** (MiSTer .123 y .88) pero con dos bugs: **attract con texto
  "scrambled"** y **la partida muere en ~2 s**.
- **CAUSA RAÍZ ENCONTRADA Y CONFIRMADA: el valor de los DIP switches (`in1`).** El emu daba
  `in1 = 0xff` (mapeo de DIP incorrecto) cuando el juego espera el default de MAME `0xd6`.
  Con `in1=0xd6` la ejecución del CPU es **idéntica a MAME (3000 OUTs, cero divergencia)**.
- **FIXES YA APLICADOS en el RTL/emu** (ver abajo), **PENDIENTE: rebuild Quartus + redeploy + probar**.
- El `.rbf` que hay AHORA en las placas es el ANTIGUO (sin estos fixes) → sigue con el bug.

---

## Causa raíz (confirmada)

Trazando `R1` instrucción a instrucción, la 1ª divergencia vs MAME es en `pc=0x0104 op=0xa1 (PLO 1)`.
El código en `0x0101` (destryer_prog):
```
0101: 6a       INP 2      ; D = puerto 2 = IN1 = DIP switches
0102: fb ff    XRI 0xff   ; D = ~D
0104: a1       PLO 1      ; R1.lo = ~IN1   (R1 se usa como puntero/contador)
```
- Mi test/HW: `in1=0xff` → `R1.lo = 0x00`.
- MAME: DIP default `0xd6` → `R1.lo = 0x29`.

Con `R1` mal, el bucle de attract (handshake con la interrupción) desincroniza → el juego pone la
config de display equivocada (alta-res) durante el barrido → **texto scrambled**; y la lógica de
juego se rompe → **muere en 2 s**.

**Descartado antes de llegar aquí (todo verificado == MAME):** memoria M10K registrada, fit/timing
del build, posición de PRD, gating de interrupción, ciclos por instrucción, dot clock (360×312 @5.626).

destryer DIP default (MAME `cidelsa.cpp`): Difficulty `0x02`(Easy) | Bonus `0x04`(10000) |
Lives `0x10`(3) | Coinage `0xc0` = **`0xd6`**.

---

## Fixes YA aplicados (en disco, sin build todavía)

### 1. DIP switches — `mister/Destroyer.sv`
- `in1` ahora se carga del `.mra` por HPS (ioctl index 254) a `sw[0]`:
  ```verilog
  reg [7:0] sw[8];
  always @(posedge clk) if (ioctl_wr && (ioctl_index==8'd254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;
  wire [7:0] in1 = sw[0];
  ```
  (antes era `in1 = ~status[...]` = 0xff con OSD por defecto = INCORRECTO).
- CONF_STR: quitadas las líneas `P1O[..]` de DIP manuales → sustituidas por `"DIP;"` (MiSTer genera
  el menú DIP del `.mra`).

### 2. DIP `.mra` — `mister/Destroyer.mra`
- `<switches default="0xd6" ...>` con `ids` en orden de VALOR de bits (0→3) según MAME:
  - Difficulty `bits=0,1` ids=`Very Hard,Hard,Easy,Very Easy`
  - Bonus Life `bits=2,3` ids=`14000,10000,7000,5000`
  - Lives `bits=4,5` ids=`4,3,2,1`
  - Coinage `bits=6,7` ids=`A2.5/B5,A2/B4,A1.5/B3,A1/B2`

### 3. Velocidad CPU (bug 8×) — `mister/Destroyer.sv`
- `ce_cpu` a **reloj/8 = 447 kHz** (`acc_cpu += 447`, antes `3579`). El 1802 real hace 8 relojes
  por ciclo de máquina y `cdp1802_jl` avanza 1 ciclo de máquina por `ce_cpu`. (Bug real; el juego
  parece frame-locked, así que quizá no sea visible, pero es correcto y afecta sonido/delays.)

---

## CÓMO CONTINUAR (pasos concretos)

### Paso 1 — Rebuild del core (cuando Quartus esté libre)
```sh
cd /c/_PROYECTOS/Cidelsa/mister
rm -rf db incremental_db output_files Destroyer.qws
/c/intelFPGA_lite/17.0/quartus/bin64/quartus_sh.exe --flow compile Destroyer 2>&1 | tee build.log
# ~50 min en Lite. Verificar al final: "Full Compilation was successful" y output_files/Destroyer.rbf
# OJO: el exit code del pipe es de `tee`, NO de quartus → mirar el log, no el exit.
# NO lanzar dos builds a la vez (chocan en db/). Verificar antes: tasklist | grep -i quartus
```
El fix es solo del emu (RTL sintetizable ya cabía 22% ALMs y cerraba timing +15.9 ns). Debería
compilar igual que build 3/4 (exitosos).

### Paso 2 — Redeploy a las placas (script paramiko listo)
```bash
python - <<'PY'
import paramiko, os
for host in ["192.168.5.123","192.168.5.88"]:
    c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username="root", password="1", timeout=25, look_for_keys=False, allow_agent=False)
    sftp=c.open_sftp()
    for lp,rp in [
      (r"C:/_PROYECTOS/Cidelsa/mister/output_files/Destroyer.rbf","/media/fat/_Arcade/cores/Destroyer.rbf"),
      (r"C:/_PROYECTOS/Cidelsa/mister/Destroyer.mra","/media/fat/_Arcade/Destroyer.mra"),
    ]:
        sftp.put(lp,rp); print(host, os.path.basename(lp), sftp.stat(rp).st_size)
    sftp.close(); c.exec_command("sync"); c.close()
PY
```
(La ROM `destryer.zip` ya está en `/media/fat/games/mame/` en ambas placas.)

### Paso 3 — Probar en la placa
- Menú → `_Arcade` → **Destroyer (Cidelsa)**. Reset del core tras cargar.
- **Ver si el attract se ve bien** (recuadro verde, "VENCE", "CIDELSA", texto legible) y si el
  juego ya no muere en 2 s. Los DIP por defecto ahora son los de MAME (0xd6).
- **Capturar screenshot para revisar** (vía SSH):
  ```python
  # dispara y baja el último screenshot del core
  # echo "screenshot" > /dev/MiSTer_cmd  ; el PNG sale en /media/fat/screenshots/destryer/
  ```

---

## Problema del render en SIM — RESUELTO 2026-07-02 ✅ (bug de CPU SHRC/SHLC)

**CAUSA RAÍZ REAL: el opcode 0x76 (SHRC/RSHR) — y su hermano 0x7E (SHLC/RSHL) — del CPU 1802 estaban
implementados como SHR/SHL PLANOS, sin inyectar DF en bit7/bit0.** (`rtl/cpu/cdp1802_jl.v:186,197`).
- 0x76 SHRC debe ser `D=(D>>1)|(DF<<7); DF=old D[0]`. Estaba `nd={1'b0,D[7:1]}` (metía 0 en bit7).
- 0x7E SHLC debe ser `D=(D<<1)|DF; DF=old D[7]`. Estaba `nd={D[6:0],1'b0}` (metía 0 en bit0).
- FIX: `4'h6: nd={DF,D[7:1]}` y `4'he: nd={D[6:0],DF}`. (Las versiones planas 0xF6/0xFE quedan igual.)

**Cómo se encontró (método reproducible):** traza de TODAS las escrituras de memoria (`define WRITETRACE`
en cidelsa_machine, PC incluido) sim vs MAME (`debug/destryer/play/wt.lua`) → los **7843 primeros writes
IDÉNTICOS**, 1ª divergencia en NVRAM `0x20f5`: MAME=0xd8, sim=0x58 (bit7). El PC (0x0081) apunta a una
rutina de sign-extend de offset (`0070: LDA R3; SHL; BDF; ... 007f: SHRC; 0080: STR R2`) que usa SHRC
para restaurar el byte con el signo → el SHRC roto perdía bit7 → puntero de pantalla mal → el juego
escribía las letras/caja (páginas) a direcciones erróneas que caían en char RAM con `cmem=0`
corrompiendo el glyph 0xff → "mar de tiles" ondulado = el scramble.

**Verificado tras el fix:** char writes ahora TODOS `cmem=1` (0 con cmem=0, == MAME); glyph 0xff = `00`×8
(blanco, == MAME); **render del attract LIMPIO** (caja verde + "CIDELSA", `debug/destryer/play/rgb_attract_fix.png`).
**OUTs revalidados (tb_outtrace_slow MAME_CLK=1 vs io_trace_r1_mame.txt):** ~2682 OUTs intermedios
byte-idénticos en port/data/pc; las únicas 12 líneas divergentes están TODAS dentro del bucle de sync de
vídeo (pc=0bce/00c7/00cd/00d8/0bbd) = distinto nº de spins por fase PRD/raster (residual benigno conocido).

**Cambio adicional (correctness, no era el bug):** IN0[7]/PCB pasó a leerse por `char_idx` (column-based,
como `cidelsa_charram_r`) en vez de `pcb_idx` (pmd, que es de `cidelsa_pcb_r`, solo color de display).
`cidelsa_machine.v:156`.

**Implicación HW:** este bug afectaba también al `.rbf` ya compilado → hay que **REBUILD Quartus** con el
CPU corregido antes del deploy (el `.rbf` actual arregla el DIP pero NO el scramble).

---
## (histórico) Investigación previa del render — NO era esto

**Ambas hipótesis previas quedaron REFUTADAS antes de dar con el SHRC:**

Ambas hipótesis previas quedaron REFUTADAS:
1. ❌ **Fase de reset/clock**: con `MAME_CLK=1` (dot 5.7143, la config de los 3000 OUTs) el render
   sigue scrambled → no es fase de dot clock. Con `MEM_ASYNC` (lectura async) idéntico → no es el
   hazard de la lectura registrada.
2. ❌ **Config-vs-raster (latch por-frame)**: la config en el sim es ESTABLE todo el frame y COINCIDE
   con la de MAME en `screen_update` (`freshorz=1 fresvert=1 dblpage=1 line9=1 bkg=2`, verificado por
   frame con `probe_freshorz.lua`). No hay cambio de config a mitad de frame.

**Cadena de evidencia (herramientas en `debug/destryer/oracle/`):**
- Ejecución I/O (3000 OUTs) == MAME, pero el CONTENIDO de VRAM diverge.
- PAGE ~igual (mismo tipo de escena; el sim va unos frames por detrás en la animación).
- Glyph **0xbe** char-def == MAME (`00 0a 1b 1b 11 1f 1f 0e`). Glyph **0xff**: MAME=blank (`00`×8),
  sim=**corrupto** (`be 00 00 00 00 00 00 e7`) → pinta líneas por toda la pantalla = el "scramble".
- Traza de char-writes (RTL `CHARTRACE` vs `charwrite_ff.lua`/`cw4.lua`): **MAME hace 3280 char writes
  todos con `cmem=1` y CERO con `cmem=0`**. El sim hace char writes con `cmem=0` (addr 0xf7c7, 0xf71f…)
  con `pmd=page[offset]=0xff` → todos caen en glyph 0xff (idx 0x7ff/0x7f8) → lo corrompen.
- MAME define cada glifo con `cmem=1`, addr 0xf400-0xf407, `pma=0`, `pmd=page[0]` variable
  (0x93,0x9f,0xc4…). El sim ejecuta ESCRITURAS A DIRECCIONES DISTINTAS → el CPU está en otro camino.

**Conclusión:** el CPU del sim DIVERGE de MAME en la rutina de redefinición de chars del attract
(los OUTs reconvergen, por eso los 3000 coinciden, pero las escrituras de memoria no). La divergencia
la dispara algo que el CPU **lee** y que difiere de MAME.

**Sospechoso principal — IN0[7] = bit PCB (`cdp1869_pcb_r` → `m_cdp1869_pcb`):**
- MAME (`cidelsa_v.cpp:40-46`): `m_cdp1869_pcb` se actualiza en CADA `cidelsa_charram_r`
  (incluidos los draws de display de `screen_update`) con addr **basado en `column`** (=0xff si pma[10]).
- Sim (`cidelsa_machine.v:190-193`): `pcb_in0` se latchea SOLO en lecturas de char de la CPU
  (`ce_cpu && mem_read && sel_char`) con `pcb_idx` **basado en `pmd` directo** (como `cidelsa_pcb_r`,
  no como `cidelsa_charram_r`). Asimetría de addressing Y de momento de actualización.
- El juego lee IN0[7] para sincronizar con el display; si difiere, el bucle de la rutina toma otra
  rama → `cmem`/`pma` equivocados en los char-writes → glyph 0xff corrupto.

**SIGUIENTE PASO recomendado (para clavarlo y arreglarlo):**
1. Traza instrucción-a-instrucción (PC + escrituras de memoria, no solo OUTs) sim vs MAME durante el
   attract → localizar el PRIMER PC divergente y confirmar qué lectura lo dispara (IN0[7] vs EF/PRD).
2. Alinear el camino de IN0[7]/PCB del RTL con la semántica de MAME (`m_cdp1869_pcb` = pcbram con addr
   por `column`, actualizado por las lecturas de char del 1869/display), y re-validar.

**Implicación para el HW ya compilado:** el `.rbf` con el fix de DIP sigue mereciendo deploy (arregla
el "muere en 2s" = bug R1/DIP), pero el **attract seguirá scrambled en HW** hasta arreglar esta
divergencia PCB/ejecución. Confirmar en placa cuando esté disponible.

---
### (histórico) hipótesis de config-latch — descartada
MAME `cdp1869::screen_update` renderiza con UN snapshot de config; el sim usa config viva por-scanline.
Se verificó que la config es estable y coincide → NO era el problema.

**Cómo investigar el render en sim** (herramientas ya montadas):
```sh
# tb_play con captura de frame RGB real de vis_video → PPM
cd /mnt/c/_PROYECTOS/Cidelsa/sim/verilator   # (WSL)
# build (ver comando completo en cualquiera de los runs del historial), luego:
ATTRACT_ONLY=1 MAME_CLK=1 ./obj_play/cidelsa_play 150 0     # in1=0xd6 ya está hardcodeado
# → debug/destryer/play/rgb_attract.ppm  (convertir a PNG con PIL para ver)
# comparar con snapshot real de MAME:
#   mame.exe destryer -autoboot_script debug/destryer/oracle/cap_scene_destryer.lua ... (CIDELSA_FRAME=150)
#   → debug/destryer/raw/mame_snaps/f150.png
```

---

## Validación / herramientas clave (reproducible)

- **Oráculo MAME OUTs+R1:** `debug/destryer/oracle/io_trace_r1.lua` →
  `mame.exe destryer -rompath /c/MAME/roms -autoboot_script <lua> -video none -sound none -nothrottle -seconds_to_run 60`
  → `dumps/io_trace_r1_mame.txt` (port/data/pc/R0/R1/P/X por OUT).
- **Sim OUT trace (cadencia HW):** `sim/verilator/tb_outtrace_slow.cpp` (top `cidelsa_machine`, `-DSIM`).
  `MAME_CLK=1` usa dot 5.7143 (= oráculo); sin él, 5.626 (HW real). `in1=0xd6`, `ce_cpu=447 (reloj/8)`.
  → `dumps/io_trace_live_full.txt`. **Con in1=0xd6+MAME_CLK: 3000 OUTs == MAME, 0 divergencia.**
- **Screenshots HW:** `echo "screenshot" > /dev/MiSTer_cmd` (por SSH) → `/media/fat/screenshots/<core>/`.
- MAME del usuario: `C:/MAME/mame.exe` (v0.288), romsets en `C:/MAME/roms/` (destryer/altair/draco.zip).
- Sim: Verilator en WSL (`/mnt/c/...`). Los runs con cadencia HW (ce_cpu=447) son LENTOS (~10-15 min
  para 3000 OUTs) porque la CPU va a 1/8; correr en background.

---

## Ficheros tocados en esta sesión (además de los fixes de arriba)

- `rtl/cpu/cdp1802_jl.v` — añadidos puertos debug `dbg_r1/dbg_p/dbg_x/dbg_d_out` (inertes en síntesis).
- `rtl/cidelsa_machine.v` — expone esos dbg; `ifdef MEM_ASYNC` (A/B test memoria; POR DEFECTO usa la
  M10K registrada, MEM_ASYNC NO se define en el build → sin efecto en HW).
- `rtl/vis_vram.v` — `ifdef MEM_ASYNC` idem.
- `sim/verilator/tb_outtrace_slow.cpp`, `tb_play.cpp` — instrumentación (R1/config/RGB), `in1=0xd6`,
  `ce_cpu=447`, env `MAME_CLK`/`FAST`/`ATTRACT_ONLY`.
- `mister/pll.v` — (de antes) jerarquía `pll_inst` para el clock-group (timing).

Estos cambios de debug NO afectan al bitstream (puertos dbg sin conectar en el emu → se optimizan).

---

## Pendiente global del proyecto (tras Destroyer en HW)

1. Cerrar Destroyer en HW (rebuild+deploy+test con el fix de DIP; y el render si hiciera falta).
2. Aplicar el mismo refactor M10K (y CPU reloj/8) a `draco_machine` y revalidar Draco.
3. Montar cores MiSTer separados de **Altair** (reusa `cidelsa_machine`, otra ROM) y **Draco**
   (`draco_machine`, ya validado 3000 OUTs == MAME).
