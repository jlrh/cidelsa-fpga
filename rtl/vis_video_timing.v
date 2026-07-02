// ============================================================================
//  vis_video_timing — Generador de temporización del CDP1870 (Cidelsa VIS)
// ----------------------------------------------------------------------------
//  Bloque 0. Reproduce la rejilla de raster PAL del CDP1869/1870 tal como la
//  define MAME (reference/mame/cdp1869.h, constantes set_raw + screen_update):
//
//    - Celda de 6 dots de ancho (CH_WIDTH=6). Línea total = 60*6 = 360 dots.
//    - 312 scanlines PAL.
//    - Ventana visible (la que captura el scaler) = [30,324) x [10,304) = 294x294.
//    - Área de caracteres (donde se pinta tilemap) = [54,300) x [44,260).
//    - PRD (_PREDISPLAY invertido): =1 durante scanlines [43,260), =0 el resto.
//      INT/EF1 del 1802 = ~PRD  => activos en vblank (genera la IRQ de frame).
//
//  Reloj: se avanza un dot por cada 'ce_pix' (clock-enable del dot clock).
//  El dot clock real es 5.7143 MHz (Destroyer) / 5.626 MHz (Altair/Draco); el
//  módulo es independiente de la frecuencia (sólo cuenta). El wrapper MiSTer
//  generará ce_pix desde el clk rápido.
//
//  Polaridad: hsync/vsync se emiten ACTIVOS EN ALTO durante su ventana de sync;
//  el wrapper los invierte si el scaler los quiere activo-bajo.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module vis_video_timing #(
    // ---- Horizontal (en dots; CH_WIDTH=6) ----
    parameter H_TOTAL      = 360,  // 60*6
    parameter HSYNC_START  = 336,  // 56*6
    parameter HSYNC_END    = 360,  // 60*6  (= H_TOTAL)
    parameter HBLANK_START = 324,  // 54*6  (fin de vídeo activo)
    parameter HBLANK_END   = 30,   //  5*6  (inicio de vídeo activo)
    parameter HSCREEN_START = 54,  //  9*6  (PAL: inicio área de caracteres)
    parameter HSCREEN_END   = 300, // 50*6  (fin área de caracteres)
    // ---- Vertical (en scanlines) ----
    parameter V_TOTAL      = 312,
    parameter VSYNC_START  = 308,
    parameter VSYNC_END    = 312,  // (= V_TOTAL)
    parameter VBLANK_START = 304,  // fin de vídeo activo
    parameter VBLANK_END   = 10,   // inicio de vídeo activo
    parameter VDISP_START  = 44,   // inicio área de caracteres
    parameter VDISP_END    = 260,  // fin área de caracteres
    parameter VPRED_START  = 43,   // PRD=1 desde aquí
    parameter VPRED_END    = 260   // PRD=0 desde aquí
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_pix,        // enable del dot clock (1 dot por pulso)

    output reg  [8:0]  hcount,        // 0..H_TOTAL-1
    output reg  [8:0]  vcount,        // 0..V_TOTAL-1
    output wire        hsync,         // activo-alto en ventana de sync H
    output wire        vsync,         // activo-alto en ventana de sync V
    output wire        hblank,        // 1 = fuera de vídeo activo (H)
    output wire        vblank,        // 1 = fuera de vídeo activo (V)
    output wire        de,            // display-enable: ventana visible 294x294
    output wire        display,       // área de caracteres (inner)
    output wire        predisplay,    // PRD (1 en [VPRED_START,VPRED_END))
    output wire        prd_int        // ~PRD -> INT/EF1 del 1802 (vblank)
);

    // ---- Contadores ----
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

    // ---- Decodificación combinacional ----
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
    assign prd_int    = ~predisplay;   // INT y EF1 del 1802 (mismos, MAME prd_w)

endmodule

`default_nettype wire
