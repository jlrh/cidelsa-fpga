// ============================================================================
//  draco_sound — subsistema de sonido de DRACO: COP402 + AY-3-8910 (jt49).
// ----------------------------------------------------------------------------
//  El 1802 manda un comando de 3 bits (sndcmd, de out1 bits 5-7). El COP402
//  (cop402_jl, VALIDADO 65000 instr == MAME) lo lee por IN (~m_sound&7), ejecuta
//  su rutina y maneja el AY-3-8910 por G (control) + Q (datos):
//     G1G0:  01=write data, 10=read data, 11=latch address  →  BDIR=G[0], BC1=G[1]
//     DIN del AY = Q ; el COP402 lee el AY (G=2) por L = dout latcheado.
//  Salida: audio (suma de canales del AY) + canales A/B/C.
//
//  Relojes (Draco): COP402 e AY a 2.012160 MHz (DRACO_SND_CHR1). ce_cop = enable de
//  instrucción del COP402 (CKI/16); ce_ay = enable del reloj del AY.
// ============================================================================
`default_nettype none

module draco_sound (
    input  wire        clk,
    input  wire        ce_cop,        // enable de instrucción del COP402
    input  wire        ce_ay,         // enable del reloj del AY-3-8910
    input  wire        reset,         // activo-alto

    input  wire [2:0]  sndcmd,        // comando de sonido del 1802 (out1 bits 5-7)

    output wire signed [15:0] audio,  // mezcla de los 3 canales del AY
    // debug
    output wire [9:0]  dbg_cop_pc,
    output wire [3:0]  dbg_cop_g,
    output wire [7:0]  dbg_cop_q
);
    // ---- COP402 ----
    wire [3:0] cop_g;
    wire [7:0] cop_q;
    wire [3:0] cop_d;
    reg  [7:0] psg_dout_latch;   // dato leído del AY (G=2) → L del COP402

    cop402_jl u_cop (
        .clk(clk), .ce(ce_cop), .reset(reset),
        .in_in({1'b0, ~sndcmd}),      // IN = ~m_sound & 7
        .l_in(psg_dout_latch),        // L = dato del AY (lectura)
        .g_out(cop_g), .q_out(cop_q), .d_out(cop_d), .l_out(),
        .sk_out(),
        .dbg_pc(dbg_cop_pc), .dbg_a(), .dbg_b(),
        .dbg_g(dbg_cop_g), .dbg_q(dbg_cop_q), .dbg_en(), .dbg_skip()
    );

    // ---- AY-3-8910 (jt49_bus): BDIR=G[0], BC1=G[1], DIN=Q ----
    wire        bdir = cop_g[0];
    wire        bc1  = cop_g[1];
    wire [7:0]  ay_dout;
    wire [9:0]  ay_sound;
    wire [7:0]  ay_A, ay_B, ay_C;
    wire        ay_sample;

    // latch del dato del AY cuando el COP402 lo lee (G=2: read data)
    always @(posedge clk) begin
        if (reset) psg_dout_latch <= 8'd0;
        else if (cop_g == 4'd2) psg_dout_latch <= ay_dout;
    end

    jt49_bus u_ay (
        .rst_n(~reset), .clk(clk), .clk_en(ce_ay),
        .bdir(bdir), .bc1(bc1), .din(cop_q),
        .sel(1'b1),                    // sin dividir el reloj
        .dout(ay_dout), .sound(ay_sound),
        .A(ay_A), .B(ay_B), .C(ay_C), .sample(ay_sample),
        .IOA_in(8'h00), .IOA_out(), .IOA_oe(),
        .IOB_in(8'h00), .IOB_out(), .IOB_oe()
    );

    // mezcla: sound es 10-bit unsigned → centrar y escalar a 16-bit con signo
    assign audio = {1'b0, ay_sound, 5'd0} - 16'sd16384;
endmodule

`default_nettype wire
