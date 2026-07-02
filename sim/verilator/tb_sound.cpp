// ============================================================================
//  tb_sound — autoverifica vis_sound: periodo del tono = D (fórmula MAME) y que
//  el LFSR del ruido varía (no se atasca).
// ============================================================================
#include "Vvis_sound.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cmath>

static Vvis_sound* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

int main(int argc, char** argv){
    Verilated::commandArgs(argc, argv);
    dut = new Vvis_sound;
    int fails=0;
    dut->ce_pix=1; dut->clk=0;
    dut->reset=1; dut->eval(); for(int i=0;i<4;i++) tick(); dut->reset=0;

    // --- TONO: tonefreq=5 -> base=16 ; tonediv=60 -> *61 ; D=976. toggle cada D ---
    dut->tonefreq=5; dut->tonediv=60; dut->toneamp=8; dut->toneoff=0;
    dut->wnoff=1; dut->wnamp=0; dut->wnfreq=0;
    int D_exp = (512>>5)*(60+1);
    // medir ciclos entre cambios de signo del audio
    int prev = (int16_t)dut->audio; int prevsign = prev>=0?1:-1;
    long last=0; int meas=0, ok=0;
    for(long t=0;t<200000 && meas<6;t++){
        tick();
        int a=(int16_t)dut->audio; int s=a>=0?1:-1;
        if(s!=prevsign){
            long per=t-last; last=t;
            if(meas>0){ if((int)per==D_exp) ok++; if(meas<=3) printf("  tono semiperiodo=%ld (esperado %d) %s\n",per,D_exp,(int)per==D_exp?"OK":"FAIL"); }
            meas++; prevsign=s;
        }
    }
    if(ok>=3) printf("[PASS] tono: semiperiodo = D = %d ciclos de dot\n",D_exp); else { printf("[FAIL] tono\n"); fails++; }

    // --- RUIDO: toneoff, wn on. Comprobar que el audio varía (LFSR no atascado) ---
    dut->toneoff=1; dut->wnoff=0; dut->wnamp=8; dut->wnfreq=3;  // ndiv=512
    int seen0=0, seen1=0; int prevn=-99;
    for(long t=0;t<300000;t++){
        tick();
        int a=(int16_t)dut->audio;
        if(a>0) seen1++; else if(a<0) seen0++;
    }
    if(seen0>100 && seen1>100) printf("[PASS] ruido: LFSR varía (neg=%d pos=%d)\n",seen0,seen1);
    else { printf("[FAIL] ruido atascado (neg=%d pos=%d)\n",seen0,seen1); fails++; }

    printf(fails?">>> %d FALLOS\n":">>> TODO OK\n",fails);
    delete dut; return fails?1:0;
}
