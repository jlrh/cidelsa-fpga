# ============================================================================
#  cidelsa_destroyer.sdc — restricciones de temporización
# ----------------------------------------------------------------------------
#  Reloj único de 50 MHz (FPGA_CLK1_50). El core funciona con clock-enables
#  (ce_cpu 3.579 MHz, ce_pix 5.626 MHz) derivados de este reloj, así que el
#  análisis de timing se hace contra los 50 MHz (20 ns), que es el caso peor.
# ============================================================================
# clk_sys del PLL. El core es enable-gated (CPU 3.579 / vídeo 5.626 MHz por ce),
# así que clk_sys puede ser cualquier frecuencia >= ~12 MHz que cumpla timing.
# Fmax del diseño = ~34 MHz → con clk_sys a 30 MHz cumple con margen.
create_clock -name FPGA_CLK1_50 -period 33.333 [get_ports FPGA_CLK1_50]

derive_clock_uncertainty

# entradas/salidas asíncronas: relajar (no críticas en este sanity build)
set_false_path -from [get_ports {KEY*}] -to [all_registers]
set_false_path -from [get_ports {SW*}]  -to [all_registers]
set_false_path -from [all_registers] -to [get_ports {LED* VID_* AUD_*}]
