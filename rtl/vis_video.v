`timescale 1ns/1ps
`default_nettype none

module vis_video (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_pix,

    input  wire [2:0]  bkg,
    input  wire        cfc,
    input  wire [1:0]  col,
    input  wire        dispoff,
    input  wire        freshorz,
    input  wire        fresvert,
    input  wire        line9,
    input  wire        line16,
    input  wire        dblpage,
    input  wire [10:0] hma,
    input  wire        draco,

    input  wire        flip,

    output wire [10:0] page_addr,
    input  wire [7:0]  page_q,
    output wire [10:0] char_addr,
    input  wire [7:0]  char_q,
    output wire [10:0] pcb_addr,
    input  wire        pcb_q,

    output wire [8:0]  hcount,
    output wire [8:0]  vcount,
    output wire        hsync,
    output wire        vsync,
    output wire        de,
    output wire        prd_int,
    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b
);
    localparam PIPE = 2;

    wire [8:0] hc_raw, vc_raw;
    wire hs_raw, vs_raw, de_raw, hbl, vbl, disp_raw, pred_raw, prd_raw;
    vis_video_timing u_timing (
        .clk(clk), .reset(reset), .ce_pix(ce_pix),
        .hcount(hc_raw), .vcount(vc_raw),
        .hsync(hs_raw), .vsync(vs_raw), .hblank(hbl), .vblank(vbl),
        .de(de_raw), .display(disp_raw), .predisplay(pred_raw), .prd_int(prd_raw)
    );

    localparam HSCREEN_START = 54, HSCREEN_END = 300;
    localparam VDISP_START   = 44, VDISP_END   = 260;

    wire [4:0] lines  = (line16 && !dblpage) ? 5'd16 : (!line9 ? 5'd9 : 5'd8);
    wire [5:0] height = fresvert ? {1'b0,lines} : {lines,1'b0};
    wire [3:0] width  = freshorz ? 4'd6  : 4'd12;
    wire [5:0] cols   = freshorz ? 6'd40 : 6'd20;
    reg  [5:0] rows;
    always @(*) begin
        case (height)
            6'd8:    rows = 6'd27;
            6'd9:    rows = 6'd24;
            6'd16:   rows = 6'd13;
            6'd18:   rows = 6'd12;
            6'd32:   rows = 6'd6;
            default: rows = 6'd27;
        endcase
    end

    reg  [15:0] pmemsize;
    always @(posedge clk) pmemsize <= ((cols * rows) << (dblpage?1:0)) << (line16?1:0);

    reg  [15:0] rowbase_max;
    always @(posedge clk) rowbase_max <= (rows - 6'd1) * cols;

    reg [5:0] cell_x;
    reg [3:0] col_in;
    always @(posedge clk) begin
        if (reset) begin cell_x <= 6'd0; col_in <= 4'd0; end
        else if (ce_pix) begin
            if (hc_raw == HSCREEN_START-1) begin col_in <= 4'd0; cell_x <= 6'd0; end
            else if (hc_raw >= HSCREEN_START && hc_raw < HSCREEN_END) begin
                if (col_in == width-4'd1) begin col_in <= 4'd0; cell_x <= cell_x + 6'd1; end
                else                          col_in <= col_in + 4'd1;
            end
        end
    end

    reg [5:0]  cell_y;
    reg [5:0]  line_in;
    reg [15:0] page_base;
    always @(posedge clk) begin
        if (reset) begin cell_y <= 6'd0; line_in <= 6'd0; page_base <= 16'd0; end
        else if (ce_pix && hc_raw == 9'd0) begin
            if (vc_raw == VDISP_START) begin
                line_in <= 6'd0; cell_y <= 6'd0; page_base <= 16'd0;
            end else if (vc_raw > VDISP_START && vc_raw < VDISP_END) begin
                if (line_in == height-6'd1) begin
                    line_in <= 6'd0; cell_y <= cell_y + 6'd1; page_base <= page_base + {10'd0,cols};
                end else line_in <= line_in + 6'd1;
            end
        end
    end

    wire [5:0] cma_raw = fresvert ? line_in : (line_in >> 1);

    wire [5:0] cma = flip ? ({1'b0,lines} - 6'd1 - cma_raw) : cma_raw;
    wire [2:0] px6 = freshorz ? col_in[2:0] : col_in[3:1];

    wire in_hdisp = (hc_raw >= HSCREEN_START) && (hc_raw < HSCREEN_END);
    wire in_vdisp = (vc_raw >= VDISP_START)   && (vc_raw < VDISP_END);
    wire in_grid  = in_hdisp && in_vdisp && (cell_x < cols) && (cell_y < rows);

    wire [5:0]  cell_x_eff    = flip ? (cols - 6'd1 - cell_x) : cell_x;
    wire [15:0] page_base_eff = flip ? (rowbase_max - page_base) : page_base;
    wire [15:0] page_a0   = {5'd0, hma} + page_base_eff + {10'd0, cell_x_eff};
    wire [15:0] page_full = (page_a0 >= pmemsize) ? (page_a0 - pmemsize) : page_a0;

    assign page_addr = draco ? page_full[10:0] : {1'b0, page_full[9:0]};
    wire        col10_0 = page_full[10];

    reg        col10_1;
    reg [5:0]  cma_1;
    always @(posedge clk) if (ce_pix) begin col10_1 <= col10_0; cma_1 <= cma; end

    wire [7:0] pmd     = page_q;

    wire [7:0] column  = col10_1 ? 8'hff : pmd;
    wire [7:0] charsel = draco ? pmd : column;
    assign char_addr = (({3'd0,charsel} << 3) | {8'd0,(cma_1[2:0] & 3'd7)}) & 11'h7ff;
    assign pcb_addr  = (({3'd0,pmd}     << 3) | {8'd0,(cma_1[2:0] & 3'd7)}) & 11'h7ff;

    reg [2:0] px6_d1, px6_d2;
    reg       grid_d1, grid_d2;
    always @(posedge clk) if (ce_pix) begin
        px6_d1 <= px6;     px6_d2 <= px6_d1;
        grid_d1 <= in_grid; grid_d2 <= grid_d1;
    end

    wire pix_on = flip ? char_q[px6_d2] : char_q[3'd5 - px6_d2];
    wire ccb0   = char_q[6];
    wire ccb1   = char_q[7];
    wire pcb_b  = pcb_q;

    reg rc, bc, gc;
    always @(*) begin
        case (col)
            2'd0:    begin rc=ccb0;  bc=ccb1; gc=pcb_b; end
            2'd1:    begin rc=ccb0;  bc=pcb_b; gc=ccb1; end
            default: begin rc=pcb_b; bc=ccb0; gc=ccb1; end
        endcase
    end
    wire [2:0] color3   = {rc, bc, gc};
    wire [6:0] pen_char = cfc ? (color3 + ((bkg + 3'd1) << 3)) : {4'd0, color3};
    wire [6:0] pen      = (grid_d2 && pix_on && !dispoff) ? pen_char : {4'd0, bkg};

    wire [7:0] pr, pg, pb;
    vis_palette u_pal (.pen(pen), .r(pr), .g(pg), .b(pb));

    reg [8:0] hc_d [0:PIPE-1];
    reg [8:0] vc_d [0:PIPE-1];
    reg [PIPE-1:0] hs_d, vs_d, de_d, prd_d;
    integer i;
    always @(posedge clk) if (ce_pix) begin
        hc_d[0] <= hc_raw; vc_d[0] <= vc_raw;
        hs_d[0] <= hs_raw; vs_d[0] <= vs_raw; de_d[0] <= de_raw; prd_d[0] <= prd_raw;
        for (i=1; i<PIPE; i=i+1) begin
            hc_d[i] <= hc_d[i-1]; vc_d[i] <= vc_d[i-1];
            hs_d[i] <= hs_d[i-1]; vs_d[i] <= vs_d[i-1];
            de_d[i] <= de_d[i-1]; prd_d[i] <= prd_d[i-1];
        end
    end

    assign hcount  = hc_d[PIPE-1];
    assign vcount  = vc_d[PIPE-1];
    assign hsync   = hs_d[PIPE-1];
    assign vsync   = vs_d[PIPE-1];
    assign de      = de_d[PIPE-1];
    assign prd_int = prd_d[PIPE-1];

    assign r = de ? pr : 8'd0;
    assign g = de ? pg : 8'd0;
    assign b = de ? pb : 8'd0;

endmodule

`default_nettype wire
