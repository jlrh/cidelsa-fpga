// ============================================================================
//  tb_live — sistema Destroyer COMPLETO corriendo "vivo" (CPU + vídeo).
//  Genera ce_cpu (3.579 MHz) y ce_pix (dot 5.7143 MHz) desde un clk rápido,
//  corre N frames y vuelca el último frame de vídeo a PPM. También cuenta OUTs.
//    salida: debug/destryer/raw/sim_snaps/live.ppm
//  uso: tb_live [frames]   (def 600)
// ============================================================================
#include "Vcidelsa_machine.h"
#include "Vcidelsa_machine___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vcidelsa_machine* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

static const int VX0=30, VY0=10, VW=294, VH=294;
static uint8_t buf[VH][VW][3];

int main(int argc, char** argv){
    Verilated::commandArgs(argc, argv);
    dut = new Vcidelsa_machine;
    int FRAMES = (argc>1)? atoi(argv[1]) : 600;

    dut->in0=0xff; dut->in1=0xff; dut->ef_ext=0; dut->clk=0;
    dut->ce_cpu=0; dut->ce_pix=0;
    dut->reset=1; dut->eval();
    // unos ticks de reset (ce activos)
    for(int i=0;i<8;i++){ dut->ce_cpu=1; dut->ce_pix=1; tick(); }
    dut->reset=0;

    long acc=0, frames=0, outs=0;
    int pv=1, ph=1;
    FILE* ft=fopen("../../debug/destryer/dumps/io_trace_live.txt","w");
    int prevout=0;
    long maxticks = (long)FRAMES*120000 + 200000;
    for(long t=0; t<maxticks && frames<FRAMES; t++){
        dut->ce_pix = 1;
        acc += 3579; int cce = 0; if(acc >= 5714){ acc -= 5714; cce=1; }
        dut->ce_cpu = cce;
        tick();
        int outnow = dut->io_active && dut->io_is_out;
        if(outnow && !prevout){ outs++; if(outs<=200) fprintf(ft,"%ld port=%d data=0x%02x rx=0x%04x\n",outs,dut->io_port,dut->io_data,dut->io_addr); }
        prevout = outnow;
        // capturar pixel visible
        if(dut->de){
            int x=dut->hcount-VX0, y=dut->vcount-VY0;
            if(x>=0&&x<VW&&y>=0&&y<VH){ buf[y][x][0]=dut->r; buf[y][x][1]=dut->g; buf[y][x][2]=dut->b; }
        }
        // detectar fin de frame (vcount,hcount -> 0,0)
        if(dut->hcount==0 && dut->vcount==0 && (ph||pv)){ frames++; }
        ph = dut->hcount; pv = dut->vcount;
    }

    FILE* fo=fopen("../../debug/destryer/raw/sim_snaps/live.ppm","w");
    fprintf(fo,"P3\n%d %d\n255\n",VW,VH);
    for(int y=0;y<VH;y++) for(int x=0;x<VW;x++)
        fprintf(fo,"%d %d %d ",buf[y][x][0],buf[y][x][1],buf[y][x][2]);
    fclose(fo);
    fclose(ft);
    // config de display en el frame capturado
    int cfg=dut->dbg_cfg;
    printf(">>> %ld frames, %ld OUTs -> live.ppm\n", frames, outs);
    printf("    cfg: bkg=%d col=%d cfc=%d freshorz=%d fresvert=%d line9=%d line16=%d dblpage=%d dispoff=%d hma=0x%x\n",
        cfg&7, (cfg>>3)&3, (cfg>>5)&1, (cfg>>6)&1, (cfg>>7)&1, (cfg>>8)&1, (cfg>>9)&1, (cfg>>10)&1, (cfg>>11)&1, dut->dbg_hma);
    // volcar VRAM viva
    auto rp = dut->rootp;
    FILE* fp=fopen("../../debug/destryer/dumps/live_page.hex","w");
    for(int i=0;i<1024;i++) fprintf(fp,"%02x\n", rp->cidelsa_machine__DOT__u_vram__DOT__page_mem[i]); fclose(fp);
    FILE* fc=fopen("../../debug/destryer/dumps/live_char.hex","w");
    for(int i=0;i<2048;i++) fprintf(fc,"%02x\n", rp->cidelsa_machine__DOT__u_vram__DOT__char_mem[i]); fclose(fc);
    FILE* fpc=fopen("../../debug/destryer/dumps/live_pcb.hex","w");
    for(int i=0;i<2048;i++) fprintf(fpc,"%02x\n", rp->cidelsa_machine__DOT__u_vram__DOT__pcb_mem[i]&1); fclose(fpc);
    delete dut; return 0;
}
