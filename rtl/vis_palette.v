// ============================================================================
//  vis_palette — Paleta de 72 entradas del CDP1869/1870 → RGB (888)
// ----------------------------------------------------------------------------
//  Bloque 3 (color). Réplica de get_rgb + cdp1869_palette (reference/mame/cdp1869.cpp).
//    pen 0..7   : color-on-color  = get_rgb(c=pen, l=15)  (luma plena = 255)
//    pen 8..71  : tone-on-tone    = get_rgb(c=(pen-8)/8, l=(pen-8)%8)
//  get_rgb(c,l): luma = (l&4?30:0)+(l&1?59:0)+(l&2?11:0); luma8 = luma*255/100
//                R = c&4?luma8:0 ; G = c&1?luma8:0 ; B = c&2?luma8:0
//  Combinacional (LUT). Pesos R30/G59/B11.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module vis_palette (
    input  wire [6:0] pen,      // 0..71
    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b
);
    // luma de 3 bits (l) -> componente de 8 bits (= l*255/100 con los pesos aplicados)
    //  l=0:0  1:59->150  2:11->28  3:70->178  4:30->76  5:89->226  6:41->104  7:100->255
    function [7:0] luma8;
        input [2:0] l;
        case (l)
            3'd0: luma8 = 8'd0;
            3'd1: luma8 = 8'd150;
            3'd2: luma8 = 8'd28;
            3'd3: luma8 = 8'd178;
            3'd4: luma8 = 8'd76;
            3'd5: luma8 = 8'd226;
            3'd6: luma8 = 8'd104;
            3'd7: luma8 = 8'd255;
        endcase
    endfunction

    reg [2:0] c;
    reg [2:0] l;
    reg [7:0] lv;
    always @(*) begin
        l = 3'd0;                 // default (evita latch; sólo se usa en la rama else)
        if (pen < 7'd8) begin
            c  = pen[2:0];
            lv = 8'd255;          // l=15 -> luma plena
        end else begin
            c  = (pen - 7'd8) >> 3;   // (pen-8)/8  -> 0..7
            l  = (pen - 7'd8) & 3'd7; // (pen-8)%8
            lv = luma8(l);
        end
        r = c[2] ? lv : 8'd0;   // bit2 -> R
        g = c[0] ? lv : 8'd0;   // bit0 -> G
        b = c[1] ? lv : 8'd0;   // bit1 -> B
    end
endmodule

`default_nettype wire
