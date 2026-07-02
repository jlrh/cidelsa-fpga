# Restricciones de tiempo del core World Rally.
# derive_pll_clocks crea los relojes de TODAS las PLL (la del core a 96 MHz + las de sys/).
# derive_clock_uncertainty anade la incertidumbre. sys/ aporta el resto (HPS, HDMI, etc.).
derive_pll_clocks
derive_clock_uncertainty

# ---------------------------------------------------------------------------
#  Multicycle de los dominios con CLOCK-ENABLE (un solo reloj de 96 MHz + cen).
#
#  El core corre todo a 96 MHz y deriva las velocidades reales por clock-enable:
#    68000 = clk/8 (12 MHz)   R8051/DS5002 = clk/8   OKI = clk/96   pixel = clk/14
#  Su logica combinacional dispone de >=4 ciclos de 96 MHz, no de 1. Sin esto, el
#  datapath del 8051 (MUL/DIV) y los pipelines del 68k/wram violan setup a 96 MHz.
#
#  Se usa MULTICYCLE 2 (CONSERVADOR): 20.8 ns, suficiente para los ~15 ns de los
#  peores paths, y SEGURO porque la separacion real minima del cen es 4 ciclos
#  (fx68k phi1<->phi2; mcu_cen y pixel son aun mayores). NO se relaja el controlador
#  SDRAM (jtframe_sdram64), que SI corre a 96 MHz real para hablar con el chip.
# ---------------------------------------------------------------------------

# Core completo MENOS el controlador SDRAM.
set core_regs [remove_from_collection \
    [get_registers -nowarn {*wrally_fpga:u_core|*}] \
    [get_registers -nowarn {*wrally_sdram:u_sdram|*}]]
if {[get_collection_size $core_regs] > 0} {
    set_multicycle_path -setup -from $core_regs -to $core_regs 2
    set_multicycle_path -hold  -from $core_regs -to $core_regs 1
}

# Mezclador de video del framework MiSTer: corre en CLK_VIDEO (=clk 96 MHz) con
# CE_PIXEL (= ce_pix del core, clk/14), asi que su hq2x/scandoubler tiene >=7 ciclos.
set vid_regs [get_registers -nowarn {*video_mixer*}]
if {[get_collection_size $vid_regs] > 0} {
    set_multicycle_path -setup -from $vid_regs -to $vid_regs 2
    set_multicycle_path -hold  -from $vid_regs -to $vid_regs 1
}

# ============================================================================
#  SDRAM_CLK + timing de I/O de la SDRAM — ADAPTADO DE jtframe sdram_clk96.sdc
#  (jotego/jtcores, fuente de verdad; mismo controlador jtframe_sdram64).
#
#  wrally NO tenia NINGUNA restriccion de SDRAM: STA no conocia SDRAM_CLK como reloj,
#  asi que NO modelaba la captura de la lectura -> el fitter colocaba el FF de captura
#  de forma arbitraria -> lecturas SDRAM corruptas SOLO en HW (la pantalla negra que
#  quedaba tras arreglar las escrituras). El modelo Micron en sim tiene timing ideal y
#  no lo reproducia. SDRAM_CLK se genera por DDIO (altddio_out, ver wrally.sv) a 180
#  grados de 'clk' (PLL outclk_0 = general[0]); aqui se DECLARA ese 180 a STA.
#  Nodos verificados contra el netlist V.006 (mister/verify_sdram_nodes.tcl):
#    PLL general[0]=1, dout=16, dq_pad=16, sdram_a=15, SDRAM_DQ=16, SDRAM_CLK=1.
# ============================================================================
create_generated_clock -name SDRAM_CLK -source \
    [get_pins {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -divide_by 1 -phase 180 \
    [get_ports SDRAM_CLK]

# Relaja las transferencias SDRAM_CLK <-> clk a 2 ciclos (igual que jtframe).
set_multicycle_path -from [get_clocks {SDRAM_CLK}] \
    -to [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup -end 2
set_multicycle_path -from [get_clocks {SDRAM_CLK}] \
    -to [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold -end 2

# Timing de I/O del controlador jtframe_sdram64 (2 ciclos). Registros verificados:
#   dout = captura de lectura (dout<=sdram_dq) ; dq_pad = dato de escritura.
set_multicycle_path -setup -end -from [get_keepers {SDRAM_DQ[*]}] \
    -to [get_keepers {*jtframe_sdram64:u_sdram|dout[*]}] 2
# V.012: HOLD multicycle de LECTURA (faltaba; el path de escritura sí lo tenía). jtframe pone
# setup Y hold en SDRAM_DQ->clk. Sin el hold, STA analiza mal el hold de captura -> placement
# marginal -> corrupción NO-determinista (V.011: cks_sum varía). Candidato #1 del fix SDRAM.
set_multicycle_path -hold  -end -from [get_keepers {SDRAM_DQ[*]}] \
    -to [get_keepers {*jtframe_sdram64:u_sdram|dout[*]}] 2
set_multicycle_path -setup -end -from [get_keepers {*jtframe_sdram64:u_sdram|dq_pad[*]}] \
    -to [get_keepers {SDRAM_DQ[*]}] 2
set_multicycle_path -hold  -end -from [get_keepers {*jtframe_sdram64:u_sdram|dq_pad[*]}] \
    -to [get_keepers {SDRAM_DQ[*]}] 2
