// ============================================================================
//  tb_play — valida la JUGABILIDAD en sim: attract → MONEDA (EF4) → START1 →
//  vuelca VRAM viva + NVRAM para renderizar y comprobar que arranca una partida.
//  Usa el MISMO mapeo de inputs que el emu MiSTer:
//    in0 (activo-bajo): b1=Start1, b3=Right, b4=Left, b5=Fire ; b7=PCB (lo pone el core).
//    coin1 = ef_ext[3] (EF4, activo-alto). service=ef_ext[1], coin2=ef_ext[2].
//  Salidas: debug/destryer/dumps/play_{page,char,pcb}.hex + NVRAM por consola.
//  uso: tb_play [attract_frames] [game_frames]
// ============================================================================
#include "Vcidelsa_machine.h"
#include "Vcidelsa_machine___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vcidelsa_machine* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

static long acc=0, acc_pix=0;
static int cap_cfg=0, cap_hma=0;   // config capturada a MITAD de display (como el golden)
// avanza 1 frame con los inputs dados (in0 activo-bajo, ef_ext activo-alto)
// CADENCIA HW: clk libre 30MHz, ce_pix=5.626 y ce_cpu=3.579 con hueco (memoria M10K registrada).
static long run_frames(int nframes, uint8_t in0, uint8_t ef_ext, long* outs){
    int pv=1, ph=1; long frames=0, ticks=0; int prevout=0;
    dut->in0=in0; dut->in1=0xd6; dut->ef_ext=ef_ext;
    static int FAST = getenv("FAST") ? 1 : 0;   // FAST=cadencia rápida (async); si no, HW (registrada)
    while(frames<nframes && ticks<(long)nframes*(FAST?250000:1200000)+1200000){
        int cpx, cce;
        if(FAST){ cpx=1; acc += 3579; cce=0; if(acc>=5714){ acc-=5714; cce=1; } }
        else    { acc_pix += (getenv("MAME_CLK")?5714:5626); cpx=(acc_pix>=30000); if(cpx)acc_pix-=30000;
                  // ce_cpu = CICLO DE MÁQUINA del 1802 = reloj/8 = 3.579MHz/8 = 447.375 kHz
                  acc += 447; cce=(acc>=30000); if(cce)acc-=30000; }
        dut->ce_pix=cpx; dut->ce_cpu=cce; tick(); ticks++;
        int outnow = dut->io_active && dut->io_is_out;
        if(outs){ if(outnow && !prevout) (*outs)++; }
        prevout=outnow;
        // captura la config de DISPLAY a mitad de pantalla (vcount 140..160), no en vblank
        if(dut->vcount>=140 && dut->vcount<=160){ cap_cfg=dut->dbg_cfg; cap_hma=dut->dbg_hma; }
        if(dut->hcount==0 && dut->vcount==0 && (ph||pv)) frames++;
        ph=dut->hcount; pv=dut->vcount;
    }
    return frames;
}

// Captura un frame RGB REAL de vis_video (render por-scanline en vivo = lo que ve el HW).
// Ventana visible del CDP1870: hcount [30,324) x vcount [10,304) = 294x294.
static void capture_rgb(const char* path){
    static uint8_t fb[294][294][3];
    int FAST = getenv("FAST") ? 1 : 0;
    // sincroniza a inicio de frame
    long guard=0;
    while(!(dut->hcount==0 && dut->vcount==0) && guard<2000000){
        int cpx,cce;
        if(FAST){ cpx=1; acc+=3579; cce=(acc>=5714); if(cce)acc-=5714; }
        else{ acc_pix+=5626; cpx=(acc_pix>=30000); if(cpx)acc_pix-=30000; acc+=447; cce=(acc>=30000); if(cce)acc-=30000; }
        dut->ce_pix=cpx; dut->ce_cpu=cce; tick(); guard++;
    }
    // captura un frame completo
    int seen=0; guard=0;
    while(guard<2000000){
        int cpx,cce;
        if(FAST){ cpx=1; acc+=3579; cce=(acc>=5714); if(cce)acc-=5714; }
        else{ acc_pix+=5626; cpx=(acc_pix>=30000); if(cpx)acc_pix-=30000; acc+=447; cce=(acc>=30000); if(cce)acc-=30000; }
        dut->ce_pix=cpx; dut->ce_cpu=cce; tick(); guard++;
        if(cpx){
            int x=(int)dut->hcount-30, y=(int)dut->vcount-10;
            if(x>=0&&x<294&&y>=0&&y<294){ fb[y][x][0]=dut->r; fb[y][x][1]=dut->g; fb[y][x][2]=dut->b; }
            // log CADA cambio de config con su scanline (ver dónde conmuta display<->vblank)
            static int pc=-1; int c=dut->dbg_cfg;
            if(c!=pc){ printf("      cfg CHANGE @v=%d h=%d: dbl=%d fhz=%d fvt=%d l9=%d bkg=%d cfc=%d disp=%d\n",
                dut->vcount,dut->hcount,(c>>10)&1,(c>>6)&1,(c>>7)&1,(c>>8)&1,c&7,(c>>5)&1,(c>>11)&1); pc=c; }
            if(dut->hcount==0 && dut->vcount==0){ if(seen++) break; }
        }
    }
    FILE* f=fopen(path,"wb");
    fprintf(f,"P6\n294 294\n255\n");
    for(int y=0;y<294;y++) for(int x=0;x<294;x++) fwrite(fb[y][x],1,3,f);
    fclose(f);
    printf("    [RGB] frame capturado -> %s\n", path);
}

static void dump_vram(const char* tag){
    auto rp=dut->rootp;
    FILE* fp=fopen("../../debug/destryer/play/page_ram.hex","w"); for(int i=0;i<1024;i++) fprintf(fp,"%02x\n", rp->cidelsa_machine__DOT__u_vram__DOT__page_mem[i]); fclose(fp);
    FILE* fc=fopen("../../debug/destryer/play/char_ram.hex","w"); for(int i=0;i<2048;i++) fprintf(fc,"%02x\n", rp->cidelsa_machine__DOT__u_vram__DOT__char_mem[i]); fclose(fc);
    FILE* fpc=fopen("../../debug/destryer/play/pcb_ram.hex","w"); for(int i=0;i<2048;i++) fprintf(fpc,"%02x\n", rp->cidelsa_machine__DOT__u_vram__DOT__pcb_mem[i]&1); fclose(fpc);
    printf("    [%s] VRAM volcada (play/{page,char,pcb}_ram.hex)\n", tag);
}

static void nvram_sum(const char* tag){
    auto rp=dut->rootp; int nz=0; long sum=0;
    for(int i=0;i<256;i++){ uint8_t v=rp->cidelsa_machine__DOT__nvram[i]; if(v)nz++; sum+=v; }
    printf("    [NVRAM %s] no-cero=%d suma=%ld  primeros16: ", tag, nz, sum);
    for(int i=0;i<16;i++) printf("%02x ", rp->cidelsa_machine__DOT__nvram[i]);
    printf("\n");
}

int main(int argc, char** argv){
    Verilated::commandArgs(argc, argv);
    dut=new Vcidelsa_machine;
    int ATTRACT=(argc>1)?atoi(argv[1]):500;
    int GAME=(argc>2)?atoi(argv[2]):400;

    dut->in0=0xff; dut->in1=0xd6; dut->ef_ext=0; dut->clk=0; dut->ce_cpu=0; dut->ce_pix=0;
    dut->reset=1; dut->eval(); for(int i=0;i<8;i++){ dut->ce_cpu=1; dut->ce_pix=1; tick(); } dut->reset=0;

    long outs=0;
    printf(">>> attract %d frames\n", ATTRACT);
    run_frames(ATTRACT, 0xff, 0x0, &outs);
    nvram_sum("pre-coin");
    long outs_attract=outs;

    if(getenv("ATTRACT_ONLY")){
        int cfg=cap_cfg;
        FILE* fr=fopen("../../debug/destryer/play/regs.txt","w");
        if(fr){ fprintf(fr,"bkg=%d\ncfc=%d\ndispoff=%d\ncol=%d\nfreshorz=%d\nline9=%d\nline16=%d\ndblpage=%d\nfresvert=%d\nhma=%d\n",
            cfg&7,(cfg>>5)&1,(cfg>>11)&1,(cfg>>3)&3,(cfg>>6)&1,(cfg>>8)&1,(cfg>>9)&1,(cfg>>10)&1,(cfg>>7)&1,cap_hma); fclose(fr); }
        printf("    cfg attract: bkg=%d col=%d cfc=%d fhz=%d fvt=%d l9=%d l16=%d dbl=%d disp=%d hma=0x%x\n",
            cfg&7,(cfg>>3)&3,(cfg>>5)&1,(cfg>>6)&1,(cfg>>7)&1,(cfg>>8)&1,(cfg>>9)&1,(cfg>>10)&1,(cfg>>11)&1,cap_hma);
        dump_vram("attract");
        capture_rgb("../../debug/destryer/play/rgb_attract.ppm");
        delete dut; return 0;
    }

    printf(">>> MONEDA (EF4) 20 frames\n");
    run_frames(20, 0xff, 0x8, &outs);     // coin1 = ef_ext[3] alto
    run_frames(20, 0xff, 0x0, &outs);     // soltar
    nvram_sum("post-coin");

    printf(">>> START1 (in0 b1) 20 frames\n");
    run_frames(20, 0xfd, 0x0, &outs);     // in0 b1=0 (Start1, activo-bajo)
    run_frames(10, 0xff, 0x0, &outs);     // soltar

    printf(">>> juego %d frames\n", GAME);
    long o0=outs; run_frames(GAME, 0xff, 0x0, &outs);
    nvram_sum("post-start");
    printf("    OUTs: attract=%ld  total=%ld  (durante 'juego'=%ld)\n", outs_attract, outs, outs-o0);

    int cfg=cap_cfg;   // config de DISPLAY (mitad de pantalla)
    printf("    cfg DISPLAY: bkg=%d col=%d cfc=%d freshorz=%d fresvert=%d line9=%d line16=%d dblpage=%d dispoff=%d hma=0x%x\n",
        cfg&7,(cfg>>3)&3,(cfg>>5)&1,(cfg>>6)&1,(cfg>>7)&1,(cfg>>8)&1,(cfg>>9)&1,(cfg>>10)&1,(cfg>>11)&1,cap_hma);
    // regs.txt para el renderer
    FILE* fr=fopen("../../debug/destryer/play/regs.txt","w");
    if(fr){ fprintf(fr,"bkg=%d\ncfc=%d\ndispoff=%d\ncol=%d\nfreshorz=%d\nline9=%d\nline16=%d\ndblpage=%d\nfresvert=%d\nhma=%d\n",
        cfg&7,(cfg>>5)&1,(cfg>>11)&1,(cfg>>3)&3,(cfg>>6)&1,(cfg>>8)&1,(cfg>>9)&1,(cfg>>10)&1,(cfg>>7)&1,cap_hma); fclose(fr); }
    dump_vram("final");
    delete dut; return 0;
}
