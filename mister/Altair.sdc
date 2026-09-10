derive_pll_clocks
derive_clock_uncertainty

set core_regs [remove_from_collection \
    [get_registers -nowarn {*wrally_fpga:u_core|*}] \
    [get_registers -nowarn {*wrally_sdram:u_sdram|*}]]
if {[get_collection_size $core_regs] > 0} {
    set_multicycle_path -setup -from $core_regs -to $core_regs 2
    set_multicycle_path -hold  -from $core_regs -to $core_regs 1
}

set vid_regs [get_registers -nowarn {*video_mixer*}]
if {[get_collection_size $vid_regs] > 0} {
    set_multicycle_path -setup -from $vid_regs -to $vid_regs 2
    set_multicycle_path -hold  -from $vid_regs -to $vid_regs 1
}

create_generated_clock -name SDRAM_CLK -source \
    [get_pins {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -divide_by 1 -phase 180 \
    [get_ports SDRAM_CLK]

set_multicycle_path -from [get_clocks {SDRAM_CLK}] \
    -to [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup -end 2
set_multicycle_path -from [get_clocks {SDRAM_CLK}] \
    -to [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold -end 2

set_multicycle_path -setup -end -from [get_keepers {SDRAM_DQ[*]}] \
    -to [get_keepers {*jtframe_sdram64:u_sdram|dout[*]}] 2

set_multicycle_path -hold  -end -from [get_keepers {SDRAM_DQ[*]}] \
    -to [get_keepers {*jtframe_sdram64:u_sdram|dout[*]}] 2
set_multicycle_path -setup -end -from [get_keepers {*jtframe_sdram64:u_sdram|dq_pad[*]}] \
    -to [get_keepers {SDRAM_DQ[*]}] 2
set_multicycle_path -hold  -end -from [get_keepers {*jtframe_sdram64:u_sdram|dq_pad[*]}] \
    -to [get_keepers {SDRAM_DQ[*]}] 2
