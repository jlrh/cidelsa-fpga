// ============================================================================
//  tb_outtrace — corre el sistema vivo y vuelca TODAS las OUTs (port,data,rx,pc)
//  hasta N, para comparar con io_trace_mame.txt y localizar el 1er punto de
//  divergencia de ejecución CPU live vs MAME.
//  Ratio de cristal exacto MAME (3.579 / 5.7143 MHz).
//  uso: tb_outtrace [N]
// ============================================================================
#include "Vcidelsa_machine.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vcidelsa_machine* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

int main(int argc, char** argv){
    Verilated::commandArgs(argc, argv);
    dut = new Vcidelsa_machine;
    long N = (argc>1)? atol(argv[1]) : 3000;

    dut->in0=0xff; dut->in1=0xff; dut->ef_ext=0; dut->clk=0;
    dut->ce_cpu=0; dut->ce_pix=0; dut->reset=1; dut->eval();
    for(int i=0;i<8;i++){ dut->ce_cpu=1; dut->ce_pix=1; tick(); }
    dut->reset=0;

    long acc=0, outs=0;
    int prevout=0, ph=1, pv=1; long frames=0, fcnt=0;
    FILE* ft=fopen("../../debug/destryer/dumps/io_trace_live_full.txt","w");
    long maxticks = 200000000L;
    for(long t=0; t<maxticks && outs<N; t++){
        dut->ce_pix = 1;
        acc += 3579000; int cce=0; if(acc >= 5714300){ acc -= 5714300; cce=1; }
        dut->ce_cpu = cce;
        tick();
        int outnow = dut->io_active && dut->io_is_out;
        if(outnow && !prevout){
            outs++; fcnt++;
            fprintf(ft,"%ld port=%d data=0x%02x rx=0x%04x pc=0x%04x\n",
                outs, dut->io_port, dut->io_data, dut->io_addr, dut->dbg_pc);
        }
        prevout = outnow;
        if(dut->hcount==0 && dut->vcount==0 && (ph||pv)){
            frames++;
            if(frames>=200 && frames<=240) printf("frame %ld: %ld OUTs\n", frames, fcnt);
            fcnt=0;
        }
        ph=dut->hcount; pv=dut->vcount;
    }
    fclose(ft);
    printf(">>> %ld OUTs -> io_trace_live_full.txt\n", outs);
    delete dut; return 0;
}
