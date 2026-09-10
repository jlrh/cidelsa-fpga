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
		.output_clock_frequency0("28132387 Hz"),
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
