`timescale 1ns/1ps
`default_nettype none

module vis_palette (
    input  wire [6:0] pen,
    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b
);

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
        l = 3'd0;
        if (pen < 7'd8) begin
            c  = pen[2:0];
            lv = 8'd255;
        end else begin
            c  = (pen - 7'd8) >> 3;
            l  = (pen - 7'd8) & 3'd7;
            lv = luma8(l);
        end
        r = c[2] ? lv : 8'd0;
        g = c[0] ? lv : 8'd0;
        b = c[1] ? lv : 8'd0;
    end
endmodule

`default_nettype wire
