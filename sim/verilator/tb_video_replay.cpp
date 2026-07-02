// ============================================================================
//  tb_video_replay — replay del pipeline de vídeo (vis_video) para sim==golden.
// ----------------------------------------------------------------------------
//  vis_vram precarga PAGE/CHAR/PCB desde los volcados de MAME (con -DREPLAY).
//  Fija la config de display VERIFICADA de la escena 'tabla' y captura un frame
//  completo: cada píxel con de=1 → buf[vcount-10][hcount-30]. Escribe PPM (294x294,
//  orientación CRUDA = la del golden raw y la del bitmap de MAME).
//    salida: debug/destryer/raw/sim_snaps/tabla.ppm
// ============================================================================
#include "Vvis_video_replay_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>

static Vvis_video_replay_top* dut;
static void tick() { dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

// ventana visible (de): [30,324) x [10,304) = 294x294
static const int VX0=30, VY0=10, VW=294, VH=294;
static uint8_t buf[VH][VW][3];

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vvis_video_replay_top;

    // config de display leída de replay_scene/regs.txt (parametrizable por escena).
    // defaults = escena 'tabla' (por compat si falta el fichero).
    int rbkg=2,rcfc=0,rcol=0,rdispoff=0,rfreshorz=1,rfresvert=1,rline9=1,rline16=0,rdblpage=0,rhma=0,rdraco=0;
    FILE* fr=fopen("../../debug/destryer/replay_scene/regs.txt","r");
    if(fr){ char k[64]; int v;
        while(fscanf(fr,"%63[^=]=%d\n",k,&v)==2){
            if(!strcmp(k,"bkg"))rbkg=v; else if(!strcmp(k,"cfc"))rcfc=v; else if(!strcmp(k,"col"))rcol=v;
            else if(!strcmp(k,"dispoff"))rdispoff=v; else if(!strcmp(k,"freshorz"))rfreshorz=v;
            else if(!strcmp(k,"fresvert"))rfresvert=v; else if(!strcmp(k,"line9"))rline9=v;
            else if(!strcmp(k,"line16"))rline16=v; else if(!strcmp(k,"dblpage"))rdblpage=v;
            else if(!strcmp(k,"hma"))rhma=v; else if(!strcmp(k,"draco"))rdraco=v;
        } fclose(fr);
    } else printf("[WARN] no replay_scene/regs.txt; uso config tabla\n");
    dut->bkg=rbkg; dut->cfc=rcfc; dut->col=rcol; dut->dispoff=rdispoff;
    dut->freshorz=rfreshorz; dut->fresvert=rfresvert; dut->line9=rline9; dut->line16=rline16; dut->dblpage=rdblpage;
    dut->hma=rhma; dut->draco=rdraco;
    fprintf(stderr,"[cfg] bkg=%d cfc=%d col=%d freshorz=%d fresvert=%d line9=%d line16=%d dblpage=%d hma=%d draco=%d\n",
        rbkg,rcfc,rcol,rfreshorz,rfresvert,rline9,rline16,rdblpage,rhma,rdraco);

    dut->ce_pix=1; dut->clk=0;
    dut->reset=1; dut->eval(); for(int i=0;i<4;i++) tick(); dut->reset=0;

    // sincronizar a inicio de frame: salir de (0,0) y luego buscar el siguiente
    // (robusto frente a la latencia de pipeline, que mantiene (0,0) varios ticks).
    int guard=0;
    while(dut->hcount==0 && dut->vcount==0){ tick(); if(++guard>200000){printf("[FAIL] sale (0,0)\n");return 1;} }
    while(!(dut->hcount==0 && dut->vcount==0)){ tick(); if(++guard>400000){printf("[FAIL] no (0,0)\n");return 1;} }

    // capturar un frame completo: estamos en (0,0); capturar hasta volver a (0,0)
    // tras haber salido (la latencia de pipeline mantiene (0,0) varios ticks).
    long depx=0, de_total=0, ticks=0; int hmin=999,hmax=-1,vmin=999,vmax=-1; bool left=false;
    do {
        if (dut->de) {
            de_total++;
            if(dut->hcount<hmin)hmin=dut->hcount; if(dut->hcount>hmax)hmax=dut->hcount;
            if(dut->vcount<vmin)vmin=dut->vcount; if(dut->vcount>vmax)vmax=dut->vcount;
            int x=dut->hcount-VX0, y=dut->vcount-VY0;
            if (x>=0 && x<VW && y>=0 && y<VH) {
                buf[y][x][0]=dut->r; buf[y][x][1]=dut->g; buf[y][x][2]=dut->b; depx++;
            }
        }
        tick(); ticks++;
        if(!(dut->hcount==0 && dut->vcount==0)) left=true;
    } while(!(left && dut->hcount==0 && dut->vcount==0));
    fprintf(stderr,"[dbg] ticks=%ld de_total=%ld de h[%d..%d] v[%d..%d]\n",ticks,de_total,hmin,hmax,vmin,vmax);

    FILE* f=fopen("../../debug/destryer/raw/sim_snaps/tabla.ppm","w");
    if(!f){ printf("[FAIL] no abre ppm\n"); return 1; }
    fprintf(f,"P3\n%d %d\n255\n",VW,VH);
    for(int y=0;y<VH;y++) for(int x=0;x<VW;x++)
        fprintf(f,"%d %d %d ",buf[y][x][0],buf[y][x][1],buf[y][x][2]);
    fclose(f);
    printf(">>> frame capturado: de_px=%ld (esperado %d)  -> sim_snaps/tabla.ppm\n", depx, VW*VH);
    delete dut;
    return 0;
}
