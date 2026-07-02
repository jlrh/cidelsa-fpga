// ============================================================================
//  pll — PLL del core Destroyer: refclk 50 MHz -> outclk_0 = 30 MHz (clk_sys).
//  Instancia la megafunción altera_pll (modo direct), sin IP pregenerado.
//  El core es enable-gated (Fmax ~34 MHz) → 30 MHz cierra timing con holgura.
//
//  JERARQUÍA: módulo `pll` -> `pll_inst` (pll_core) -> `altera_pll_i`. Es OBLIGATORIA
//  para que el reloj generado se llame `*|pll|pll_inst|altera_pll_i|*|divclk` y lo
//  capture el `set_clock_groups -exclusive` de `sys/sys_top.sdc` (que false-pathea los
//  cruces con HPS/HDMI/audio). Sin el nivel `pll_inst` el reloj del core queda FUERA del
//  grupo y TimeQuest analiza los CDC como reales (slacks -17/-15/-12 ns espurios).
// ============================================================================
`timescale 1 ps / 1 ps
module pll (
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire locked
);
	pll_core pll_inst (
		.refclk(refclk),
		.rst(rst),
		.outclk_0(outclk_0),
		.locked(locked)
	);
endmodule

module pll_core (
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire locked
);
	wire [0:0] outclk;
	assign outclk_0 = outclk[0];

	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("30.000000 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst(rst),
		.outclk(outclk),
		.locked(locked),
		.fboutclk(),
		.fbclk(1'b0),
		.refclk(refclk)
	);
endmodule
