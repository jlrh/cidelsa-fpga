// ============================================================================
//  tb_video_timing — harness Verilator AUTOVERIFICABLE del bloque 0.
// ----------------------------------------------------------------------------
//  Comprueba que vis_video_timing reproduce la rejilla PAL del CDP1870:
//    - H_TOTAL=360, V_TOTAL=312, frame = 360*312 dots.
//    - hsync = [336,360) (24 dots/línea), vsync = [308,312) (4 líneas).
//    - de (ventana visible) = 294x294 = 86436 dots/frame.
//    - display (área caracteres) = 246x216 dots = (300-54)x(260-44).
//    - predisplay sube en vcount=43, baja en vcount=260; prd_int = ~predisplay.
//  Devuelve 0 si todo PASA, !=0 si algo FALLA.
// ============================================================================
#include "Vvis_video_timing.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vvis_video_timing* dut;

static void tick() {
    // un dot: flanco de bajada + flanco de subida (counters en posedge)
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vvis_video_timing;

    dut->ce_pix = 1;
    dut->reset = 1; dut->clk = 0; dut->eval();
    for (int i = 0; i < 4; i++) tick();
    dut->reset = 0;

    // Sincronizar al inicio de frame (hcount==0 && vcount==0)
    int guard = 0;
    while (!(dut->hcount == 0 && dut->vcount == 0)) { tick(); if (++guard > 200000) { printf("[FAIL] no llega a (0,0)\n"); return 1; } }

    // --- Medir un frame completo ---
    long dots = 0, de_cnt = 0, disp_cnt = 0, hsync_cnt = 0, vsync_lines = 0;
    int  hmax = 0, vmax = 0;
    int  hsync_start_ok = -1, pred_rise = -1, pred_fall = -1;
    int  prd_int_mismatch = 0;
    int  prev_vsync = 0, prev_pred = 0;
    int  hsync_first_h = 999, hsync_last_h = -1;

    // arrancamos justo en (0,0)
    do {
        int h = dut->hcount, v = dut->vcount;
        if (h > hmax) hmax = h;
        if (v > vmax) vmax = v;
        if (dut->de)      de_cnt++;
        if (dut->display) disp_cnt++;
        if (dut->hsync) { hsync_cnt++; if (h < hsync_first_h) hsync_first_h = h; if (h > hsync_last_h) hsync_last_h = h; }
        // vsync: contar líneas (en hcount==0)
        if (h == 0) { if (dut->vsync) vsync_lines++; }
        // predisplay edges
        if (dut->predisplay && !prev_pred) pred_rise = v;
        if (!dut->predisplay && prev_pred) pred_fall = v;
        prev_pred = dut->predisplay;
        // prd_int == ~predisplay
        if (dut->prd_int == dut->predisplay) prd_int_mismatch++;

        dots++;
        tick();
    } while (!(dut->hcount == 0 && dut->vcount == 0));

    // --- Chequeos ---
    int fails = 0;
    auto CHK = [&](const char* name, long got, long exp){
        bool ok = (got == exp);
        printf("  [%s] %-22s got=%ld exp=%ld\n", ok?"PASS":"FAIL", name, got, exp);
        if (!ok) fails++;
    };

    printf("Bloque 0 — vis_video_timing (PAL):\n");
    CHK("dots/frame", dots, 360L*312L);
    CHK("hcount_max", hmax, 359);
    CHK("vcount_max", vmax, 311);
    CHK("de_pixels",  de_cnt, 294L*294L);
    CHK("display_pixels", disp_cnt, (300L-54L)*(260L-44L));
    CHK("hsync_dots", hsync_cnt, 24L*312L);          // 24 dots/línea * 312 líneas
    CHK("hsync_first_h", hsync_first_h, 336);
    CHK("hsync_last_h",  hsync_last_h, 359);
    CHK("vsync_lines", vsync_lines, 4);
    CHK("predisplay_rise_v", pred_rise, 43);
    CHK("predisplay_fall_v", pred_fall, 260);
    CHK("prd_int_inv_mismatch", prd_int_mismatch, 0);

    printf(fails ? "\n>>> %d FALLO(S)\n" : "\n>>> TODO OK\n", fails);
    delete dut;
    return fails ? 1 : 0;
}
