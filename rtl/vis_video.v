// ============================================================================
//  vis_video — Pipeline de vídeo del VIS (timing + fetch + color)  [SINTETIZABLE]
// ----------------------------------------------------------------------------
//  Bloques 0+2+3. Para cada píxel reproduce screen_update del CDP1869
//  (reference/mame/cdp1869.cpp): escaneo de tilemap desde hma, fetch
//  PAGE→code→CHAR/PCB, patrón 6px + ccb, get_pen→paleta 72→RGB.
//
//  VERSIÓN SINTETIZABLE (sustituye a la combinacional de sim==golden):
//   - SIN división/módulo por píxel: contadores de celda (col_in/cell_x por dot,
//     line_in/cell_y/page_base por scanline; page_base acumula cell_y*cols).
//   - BRAM externa REGISTRADA (vis_vram, lectura en ce_pix): el fetch es un
//     pipeline de 2 etapas (PAGE en etapa 1 → CHAR/PCB en etapa 2).
//   - Las señales de timing y los selects por píxel se RETRASAN PIPE(=2) dots para
//     casar con char_q. La imagen NO se desplaza: hcount/vcount/de salen retrasados
//     junto con r/g/b, así que el consumidor (scaler / tb) sigue alineado. Esto
//     da exactamente el mismo frame que el golden (verificado en replay).
//
//  rows = 216/height resuelto por case (no divisor). pmemsize = cols*rows<<dbl<<l16
//  registrado (multiplicador de constantes de frame, fuera del path de píxel).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module vis_video (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_pix,

    // --- config de display (de vis_regs) ---
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
    input  wire        draco,         // 0=Cidelsa (Destroyer/Altair: char vía column/0xff)
                                       // 1=Draco (char vía pmd directo, page RAM 2KB)

    // --- VRAM externa (vis_vram, lectura REGISTRADA en ce_pix) ---
    output wire [10:0] page_addr,
    input  wire [7:0]  page_q,        // pmd (code)   [1 dot tras page_addr]
    output wire [10:0] char_addr,
    input  wire [7:0]  char_q,        // char_data    [1 dot tras char_addr]
    output wire [10:0] pcb_addr,
    input  wire        pcb_q,         // pcb_bit      [1 dot tras pcb_addr]

    // --- salida de vídeo (retrasada PIPE dots, alineada con r/g/b) ---
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
    localparam PIPE = 2;   // latencia datos: PAGE(1) + CHAR(1)

    // ---- Bloque 0: timing (raster crudo) ----
    wire [8:0] hc_raw, vc_raw;
    wire hs_raw, vs_raw, de_raw, hbl, vbl, disp_raw, pred_raw, prd_raw;
    vis_video_timing u_timing (
        .clk(clk), .reset(reset), .ce_pix(ce_pix),
        .hcount(hc_raw), .vcount(vc_raw),
        .hsync(hs_raw), .vsync(vs_raw), .hblank(hbl), .vblank(vbl),
        .de(de_raw), .display(disp_raw), .predisplay(pred_raw), .prd_int(prd_raw)
    );

    // ---- Geometría del área de caracteres (igual que MAME screen_update PAL) ----
    localparam HSCREEN_START = 54, HSCREEN_END = 300;   // área de caracteres (H)
    localparam VDISP_START   = 44, VDISP_END   = 260;   // área de caracteres (V), alto=216

    // ---- Constantes de frame derivadas de la config ----
    wire [4:0] lines  = (line16 && !dblpage) ? 5'd16 : (!line9 ? 5'd9 : 5'd8);
    wire [5:0] height = fresvert ? {1'b0,lines} : {lines,1'b0};   // lines o lines*2
    wire [3:0] width  = freshorz ? 4'd6  : 4'd12;
    wire [5:0] cols   = freshorz ? 6'd40 : 6'd20;
    reg  [5:0] rows;
    always @(*) begin
        case (height)
            6'd8:    rows = 6'd27;   // 216/8
            6'd9:    rows = 6'd24;   // 216/9
            6'd16:   rows = 6'd13;   // 216/16
            6'd18:   rows = 6'd12;   // 216/18
            6'd32:   rows = 6'd6;    // 216/32
            default: rows = 6'd27;
        endcase
    end
    // pmemsize = cols*rows << dblpage << line16  (constante de frame; registrada)
    reg  [15:0] pmemsize;
    always @(posedge clk) pmemsize <= ((cols * rows) << (dblpage?1:0)) << (line16?1:0);

    // ============================================================================
    //  Contadores de celda (reemplazan div/mod)
    // ============================================================================
    // Horizontal (por dot, dentro de [HSCREEN_START,HSCREEN_END))
    reg [5:0] cell_x;   // 0..cols-1
    reg [3:0] col_in;   // 0..width-1
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

    // Vertical (por scanline, evaluado en hc_raw==0). page_base acumula cell_y*cols.
    reg [5:0]  cell_y;     // 0..rows-1
    reg [5:0]  line_in;    // 0..height-1
    reg [15:0] page_base;  // cell_y*cols
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

    // ---- línea/píxel dentro de celda ----
    wire [5:0] cma = fresvert ? line_in : (line_in >> 1);   // 0..lines-1
    wire [2:0] px6 = freshorz ? col_in[2:0] : col_in[3:1];  // 0..5

    // ---- ¿dentro de la rejilla de caracteres? ----
    wire in_hdisp = (hc_raw >= HSCREEN_START) && (hc_raw < HSCREEN_END);
    wire in_vdisp = (vc_raw >= VDISP_START)   && (vc_raw < VDISP_END);
    wire in_grid  = in_hdisp && in_vdisp && (cell_x < cols) && (cell_y < rows);

    // ============================================================================
    //  ETAPA 0 (comb): dirección de PAGE desde contadores → page_addr (a BRAM)
    // ============================================================================
    wire [15:0] page_a0   = {5'd0, hma} + page_base + {10'd0, cell_x};
    wire [15:0] page_full = (page_a0 >= pmemsize) ? (page_a0 - pmemsize) : page_a0;
    // Cidelsa: page RAM 1KB → bit10=0 en la lectura (bit10 sólo alimenta column/0xff).
    // Draco:   page RAM 2KB → lectura con los 11 bits.
    assign page_addr = draco ? page_full[10:0] : {1'b0, page_full[9:0]};
    wire        col10_0 = page_full[10];

    // ---- pipeline de selects: etapa 1 (alinea con page_q) ----
    reg        col10_1;
    reg [5:0]  cma_1;
    always @(posedge clk) if (ce_pix) begin col10_1 <= col10_0; cma_1 <= cma; end

    // ============================================================================
    //  ETAPA 1 (page_q válido): CHAR/PCB addr desde pmd → char_addr/pcb_addr (a BRAM)
    // ============================================================================
    wire [7:0] pmd     = page_q;
    // Cidelsa: column = pma[10]?0xff:pmd  (truco de char redefinible).
    // Draco:   char usa pmd DIRECTO (= como el pcb), sin el truco column/0xff.
    wire [7:0] column  = col10_1 ? 8'hff : pmd;
    wire [7:0] charsel = draco ? pmd : column;
    assign char_addr = (({3'd0,charsel} << 3) | {8'd0,(cma_1[2:0] & 3'd7)}) & 11'h7ff;
    assign pcb_addr  = (({3'd0,pmd}     << 3) | {8'd0,(cma_1[2:0] & 3'd7)}) & 11'h7ff;

    // ---- pipeline de selects: etapa 2 (alinea con char_q/pcb_q) ----
    reg [2:0] px6_d1, px6_d2;
    reg       grid_d1, grid_d2;
    always @(posedge clk) if (ce_pix) begin
        px6_d1 <= px6;     px6_d2 <= px6_d1;
        grid_d1 <= in_grid; grid_d2 <= grid_d1;
    end

    // ============================================================================
    //  ETAPA 2 (char_q/pcb_q válidos): patrón + color
    // ============================================================================
    wire pix_on = char_q[3'd5 - px6_d2];
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

    // ---- paleta → RGB ----
    wire [7:0] pr, pg, pb;
    vis_palette u_pal (.pen(pen), .r(pr), .g(pg), .b(pb));

    // ============================================================================
    //  Retraso PIPE dots de las señales de timing (alinea con r/g/b)
    // ============================================================================
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
