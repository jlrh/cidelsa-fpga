// Top de REPLAY del vídeo: vis_video + vis_vram (precargada con -DREPLAY).
// Reproduce el golden (sim==golden) tras el refactor de VRAM externa.
`default_nettype none
module vis_video_replay_top (
    input  wire clk, reset, ce_pix,
    input  wire [2:0] bkg, input wire cfc, input wire [1:0] col, input wire dispoff,
    input  wire freshorz, fresvert, line9, line16, dblpage, input wire [10:0] hma,
    input  wire draco,
    output wire [8:0] hcount, vcount, output wire hsync, vsync, de,
    output wire [7:0] r, g, b
);
    wire [10:0] page_addr, char_addr, pcb_addr;
    wire [7:0]  page_q, char_q; wire pcb_q;
    vis_vram u_vram (
        .clk(clk), .ce_pix(ce_pix),
        .page_addr(page_addr), .page_q(page_q),
        .char_addr(char_addr), .char_q(char_q),
        .pcb_addr(pcb_addr),   .pcb_q(pcb_q),
        .cpu_prd_addr(11'd0), .cpu_prd_q(),
        .cpu_crd_addr(11'd0), .cpu_crd_q(),
        .cpu_pcbrd_addr(11'd0), .cpu_pcbrd_q(),
        .cpu_page_we(1'b0), .cpu_page_addr(11'd0), .cpu_page_d(8'd0),
        .cpu_char_we(1'b0), .cpu_char_addr(11'd0), .cpu_char_d(8'd0),
        .cpu_pcb_we(1'b0),  .cpu_pcb_addr(11'd0),  .cpu_pcb_d(1'b0)
    );
    vis_video u_video (
        .clk(clk), .reset(reset), .ce_pix(ce_pix),
        .bkg(bkg), .cfc(cfc), .col(col), .dispoff(dispoff),
        .freshorz(freshorz), .fresvert(fresvert), .line9(line9), .line16(line16),
        .dblpage(dblpage), .hma(hma), .draco(draco),
        .page_addr(page_addr), .page_q(page_q),
        .char_addr(char_addr), .char_q(char_q),
        .pcb_addr(pcb_addr),   .pcb_q(pcb_q),
        .hcount(hcount), .vcount(vcount), .hsync(hsync), .vsync(vsync), .de(de),
        .prd_int(), .r(r), .g(g), .b(b)
    );
endmodule
`default_nettype wire
