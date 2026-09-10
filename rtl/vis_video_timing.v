`timescale 1ns/1ps
`default_nettype none

module vis_video_timing #(

    parameter H_TOTAL      = 360,
    parameter HSYNC_START  = 336,
    parameter HSYNC_END    = 360,
    parameter HBLANK_START = 324,
    parameter HBLANK_END   = 30,
    parameter HSCREEN_START = 54,
    parameter HSCREEN_END   = 300,

    parameter V_TOTAL      = 312,
    parameter VSYNC_START  = 308,
    parameter VSYNC_END    = 312,
    parameter VBLANK_START = 304,
    parameter VBLANK_END   = 10,
    parameter VDISP_START  = 44,
    parameter VDISP_END    = 260,
    parameter VPRED_START  = 43,
    parameter VPRED_END    = 260
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_pix,

    output reg  [8:0]  hcount,
    output reg  [8:0]  vcount,
    output wire        hsync,
    output wire        vsync,
    output wire        hblank,
    output wire        vblank,
    output wire        de,
    output wire        display,
    output wire        predisplay,
    output wire        prd_int
);

    wire h_last = (hcount == H_TOTAL-1);
    wire v_last = (vcount == V_TOTAL-1);

    always @(posedge clk) begin
        if (reset) begin
            hcount <= 9'd0;
            vcount <= 9'd0;
        end else if (ce_pix) begin
            if (h_last) begin
                hcount <= 9'd0;
                vcount <= v_last ? 9'd0 : (vcount + 9'd1);
            end else begin
                hcount <= hcount + 9'd1;
            end
        end
    end

    wire h_active = (hcount >= HBLANK_END)  && (hcount < HBLANK_START);
    wire v_active = (vcount >= VBLANK_END)  && (vcount < VBLANK_START);

    assign hsync      = (hcount >= HSYNC_START) && (hcount < HSYNC_END);
    assign vsync      = (vcount >= VSYNC_START) && (vcount < VSYNC_END);
    assign hblank     = ~h_active;
    assign vblank     = ~v_active;
    assign de         = h_active && v_active;

    assign display    = (hcount >= HSCREEN_START) && (hcount < HSCREEN_END) &&
                        (vcount >= VDISP_START)    && (vcount < VDISP_END);

    assign predisplay = (vcount >= VPRED_START) && (vcount < VPRED_END);
    assign prd_int    = ~predisplay;

endmodule

`default_nettype wire
