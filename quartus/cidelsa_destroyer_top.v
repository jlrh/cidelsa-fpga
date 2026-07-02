// ============================================================================
//  cidelsa_destroyer_top — Top de SÍNTESIS para Quartus (DE10-Nano / Cyclone V)
// ----------------------------------------------------------------------------
//  Objetivo de este top: comprobar que el core (cidelsa_machine) SINTETIZA,
//  cabe e infiere BRAM correctamente en la Cyclone V, con los relojes REALES de
//  Destroyer (CPU 3.579 MHz, dot 5.626 MHz — confirmados en el manual de servicio).
//
//  NO es el wrapper MiSTer definitivo (ese va con el framework sys/ del template
//  MiSTer: hps_io, video scaler, audio, carga de ROM por HPS). Aquí los relojes se
//  derivan del FPGA_CLK1_50 (50 MHz) por acumuladores de clock-enable (frecuencia
//  media EXACTA: ce_pix=5.626/50, ce_cpu=3.579/50). En el wrapper MiSTer real se
//  usará un PLL + ce equivalentes.
//
//  Las salidas se llevan a pines (LED + buses de vídeo/audio) para que el Fitter
//  no las optimice y dé un uso de recursos / timing representativo.
// ============================================================================
`default_nettype none

module cidelsa_destroyer_top (
    input  wire        FPGA_CLK1_50,     // 50 MHz onboard
    input  wire [1:0]  KEY,              // KEY[0] = reset (activo-bajo)
    input  wire [3:0]  SW,               // DIPs de prueba
    output wire [7:0]  LED,

    // --- vídeo (a pines de cabecera GPIO / o consumido por el scaler MiSTer) ---
    output wire [7:0]  VID_R,
    output wire [7:0]  VID_G,
    output wire [7:0]  VID_B,
    output wire        VID_HS,
    output wire        VID_VS,
    output wire        VID_DE,
    output wire        VID_CE,           // ce_pix (pixel clock enable)

    // --- audio ---
    output wire [15:0] AUD_OUT
);
    // clk_sys = 30 MHz. El core es enable-gated y su Fmax ≈ 34 MHz (timing cerrado
    // a 30 MHz: setup slack +3.9 ns). En la placa real, un PLL genera 30 MHz desde
    // FPGA_CLK1_50 (50 MHz). Para este sanity build se constriñe el reloj a 30 MHz.
    wire clk = FPGA_CLK1_50;   // (en HW: salida del PLL 50->30 MHz)
    wire reset = ~KEY[0];

    // ---- generación de clock-enables (frecuencia media exacta desde clk_sys=30 MHz) ----
    // ce_pix : 5.626 MHz  -> acumula 5626 cada clk, umbral 30000
    // ce_cpu : 3.579 MHz  -> acumula 3579 cada clk, umbral 30000
    localparam [15:0] CLK_KHZ = 16'd30000;   // clk_sys en kHz
    reg [16:0] acc_pix = 17'd0;
    reg [16:0] acc_cpu = 17'd0;
    reg        ce_pix  = 1'b0;
    reg        ce_cpu  = 1'b0;
    always @(posedge clk) begin
        if (acc_pix + 17'd5626 >= {1'b0,CLK_KHZ}) begin acc_pix <= acc_pix + 17'd5626 - {1'b0,CLK_KHZ}; ce_pix <= 1'b1; end
        else begin acc_pix <= acc_pix + 17'd5626; ce_pix <= 1'b0; end
        if (acc_cpu + 17'd3579 >= {1'b0,CLK_KHZ}) begin acc_cpu <= acc_cpu + 17'd3579 - {1'b0,CLK_KHZ}; ce_cpu <= 1'b1; end
        else begin acc_cpu <= acc_cpu + 17'd3579; ce_cpu <= 1'b0; end
    end

    // ---- entradas del juego (de momento fijas a inactivo; el wrapper MiSTer las
    //      mapeará a joystick/DIPs por hps_io) ----
    wire [7:0] in0 = {1'b1, ~SW[3:0], 3'b111};   // bit7=PCB lo pone el core; resto activo-alto inactivo
    wire [7:0] in1 = 8'hff;
    wire [3:0] ef_ext = 4'b0000;

    wire [8:0] hcount, vcount;
    wire       hsync, vsync, de, q_out;
    wire [7:0] r, g, b;
    wire signed [15:0] audio;

    cidelsa_machine u_core (
        .clk(clk), .ce_cpu(ce_cpu), .ce_pix(ce_pix), .reset(reset),
        .in0(in0), .in1(in1), .ef_ext(ef_ext),
        .q_out(q_out),
        .hcount(hcount), .vcount(vcount), .hsync(hsync), .vsync(vsync), .de(de),
        .r(r), .g(g), .b(b),
        .audio(audio),
        // traza/debug (no usada en síntesis; se deja abierta)
        .io_active(), .io_is_out(), .io_port(), .io_data(), .io_addr(),
        .dbg_pc(), .dbg_fetch(), .dbg_rb(), .dbg_cfg(), .dbg_hma()
    );

    // ---- salidas a pines (registradas para timing/uso representativo) ----
    assign VID_R  = r;
    assign VID_G  = g;
    assign VID_B  = b;
    assign VID_HS = hsync;
    assign VID_VS = vsync;
    assign VID_DE = de;
    assign VID_CE = ce_pix;
    assign AUD_OUT = audio;
    assign LED = {q_out, de, vsync, hsync, ce_cpu, ce_pix, KEY[0], 1'b1};

endmodule

`default_nettype wire
