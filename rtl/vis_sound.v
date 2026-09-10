`timescale 1ns/1ps
`default_nettype none

module vis_sound (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_pix,

    input  wire [3:0]  toneamp,
    input  wire [2:0]  tonefreq,
    input  wire        toneoff,
    input  wire [6:0]  tonediv,

    input  wire [3:0]  wnamp,
    input  wire [2:0]  wnfreq,
    input  wire        wnoff,

    output wire signed [15:0] audio
);

    wire [9:0]  base_t = 10'd512 >> tonefreq;
    wire [16:0] D      = base_t * ({3'd0,tonediv} + 8'd1);
    reg  [16:0] tcnt;
    reg         tone_sq;
    always @(posedge clk) begin
        if (reset) begin tcnt <= 17'd0; tone_sq <= 1'b0; end
        else if (ce_pix) begin
            if (tcnt >= (D - 17'd1)) begin tcnt <= 17'd0; tone_sq <= ~tone_sq; end
            else                          tcnt <= tcnt + 17'd1;
        end
    end

    wire [12:0] ndiv = 13'd4096 >> wnfreq;
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

    wire signed [5:0] tone_s  = toneoff ? 6'sd0 : (tone_sq   ? $signed({2'b0,toneamp}) : -$signed({2'b0,toneamp}));
    wire signed [5:0] noise_s = wnoff   ? 6'sd0 : (noise_bit ? $signed({2'b0,wnamp})   : -$signed({2'b0,wnamp}));
    wire signed [6:0] mix     = tone_s + noise_s;
    assign audio = mix <<< 9;

endmodule

`default_nettype wire
