// ============================================================================
//  vis_sound — Sonido del CDP1869: tono (out4) + ruido blanco (out5, LFSR)
// ----------------------------------------------------------------------------
//  Bloque 7.  Fuente de verdad: sound_stream_update (reference/mame/cdp1869.cpp)
//  para el TONO; el ruido MAME NO lo implementa (TODO) → LFSR (datasheet RCA).
//
//  TONO: onda cuadrada bipolar de amplitud toneamp/15.
//    freq = (dot/2) / (512>>tonefreq) / (tonediv+1) = dot / (2*D)
//    con D = (512>>tonefreq) * (tonediv+1)  → conmuta cada D ciclos de dot (ce_pix).
//  RUIDO: LFSR de 17 bits (maximal), clockeado cada (4096>>wnfreq) ciclos de dot.
//    salida 1 bit, amplitud wnamp/15.
//  Mezcla: (tono + ruido) → muestra con signo [15:0] (la escala fina la da el wrapper).
//
//  Reloj: ce_pix = enable del dot clock (5.7143/5.626 MHz). Registros de vis_regs.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module vis_sound (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_pix,        // enable del dot clock

    // out4 (tono)
    input  wire [3:0]  toneamp,
    input  wire [2:0]  tonefreq,
    input  wire        toneoff,
    input  wire [6:0]  tonediv,
    // out5 (ruido)
    input  wire [3:0]  wnamp,
    input  wire [2:0]  wnfreq,
    input  wire        wnoff,

    output wire signed [15:0] audio
);
    // ---- TONO ----
    // D = (512 >> tonefreq) * (tonediv + 1)
    wire [9:0]  base_t = 10'd512 >> tonefreq;             // 512,256,...,4
    wire [16:0] D      = base_t * ({3'd0,tonediv} + 8'd1); // hasta 65536
    reg  [16:0] tcnt;
    reg         tone_sq;
    always @(posedge clk) begin
        if (reset) begin tcnt <= 17'd0; tone_sq <= 1'b0; end
        else if (ce_pix) begin
            if (tcnt >= (D - 17'd1)) begin tcnt <= 17'd0; tone_sq <= ~tone_sq; end
            else                          tcnt <= tcnt + 17'd1;
        end
    end

    // ---- RUIDO (LFSR 17 bits: x^17 + x^14 + 1) ----
    wire [12:0] ndiv = 13'd4096 >> wnfreq;                // 4096,2048,...,32
    reg  [12:0] ncnt;
    reg  [16:0] lfsr;
    always @(posedge clk) begin
        if (reset) begin ncnt <= 13'd0; lfsr <= 17'h1; end
        else if (ce_pix) begin
            if (ncnt >= (ndiv - 13'd1)) begin
                ncnt <= 13'd0;
                lfsr <= {lfsr[15:0], lfsr[16] ^ lfsr[13]};
            end else ncnt <= ncnt + 13'd1;
        end
    end
    wire noise_bit = lfsr[0];

    // ---- mezcla → muestra con signo ----
    //  tono: ± toneamp ; ruido: ± wnamp  (cada uno 0..15)
    wire signed [5:0] tone_s  = toneoff ? 6'sd0 : (tone_sq   ? $signed({2'b0,toneamp}) : -$signed({2'b0,toneamp}));
    wire signed [5:0] noise_s = wnoff   ? 6'sd0 : (noise_bit ? $signed({2'b0,wnamp})   : -$signed({2'b0,wnamp}));
    wire signed [6:0] mix     = tone_s + noise_s;          // ± ~30
    assign audio = mix <<< 9;                              // escala a ~±15360 (16-bit signo)

endmodule

`default_nettype wire
