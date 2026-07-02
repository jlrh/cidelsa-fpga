// ============================================================================
//  tb_outtrace_altair — trace de OUTs de Altair con cadencia HW (clk>>ce),
//  para regresión del CPU vs MAME tras el fix SHRC/SHLC. Top = altair_machine.
//  MAME_CLK=1 usa dot 5.7143 (= oráculo MAME); si no, 5.626 (HW real).
//  DIP default = 0xd6 (== Destroyer). Inputs idle. uso: tb_outtrace_altair [N]
// ============================================================================
#include "Valtair_machine.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Valtair_machine* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

int main(int argc, char** argv){
    Verilated::commandArgs(argc, argv);
    dut = new Valtair_machine;
    long N = (argc>1)? atol(argv[1]) : 3000;

    dut->in0=0xff; dut->in1=0xd6; dut->in2=0xff; dut->ef_ext=0; dut->clk=0;
    dut->ce_cpu=0; dut->ce_pix=0; dut->reset=1; dut->eval();
    for(int i=0;i<40;i++){ dut->ce_cpu=1; dut->ce_pix=1; tick(); }
    dut->reset=0;

    long acc_pix=0, acc_cpu=0, outs=0;
    int prevout=0;
    int h_port=0; unsigned h_data=0, h_pc=0, h_addr=0, h_r1=0, h_p=0, h_x=0;
    FILE* ft=fopen("../../debug/destryer/dumps/io_trace_altair_live.txt","w");
    long maxticks = 2000000000L;
    for(long t=0; t<maxticks && outs<N; t++){
        static int PIXK = getenv("MAME_CLK") ? 5714 : 5626;
        acc_pix += PIXK; int cpx=0; if(acc_pix >= 30000){ acc_pix -= 30000; cpx=1; }
        acc_cpu += 447;  int ccp=0; if(acc_cpu >= 30000){ acc_cpu -= 30000; ccp=1; }
        dut->ce_pix = cpx; dut->ce_cpu = ccp;
        tick();
        int outnow = dut->io_is_out;
        if(outnow){ h_port=dut->io_port; h_data=dut->io_data; h_pc=dut->dbg_pc; h_addr=dut->io_addr;
                    h_r1=dut->dbg_r1; h_p=dut->dbg_p; h_x=dut->dbg_x; }
        if(prevout && !outnow){
            outs++;
            fprintf(ft,"%ld port=%d data=0x%02x pc=0x%04x R0=0x%04x R1=0x%04x P=%d X=%d\n",
                outs, h_port, h_data, h_pc, h_addr, h_r1, h_p, h_x);
        }
        prevout = outnow;
    }
    fclose(ft);
    printf(">>> %ld OUTs (Altair, cadencia HW) -> io_trace_altair_live.txt\n", outs);
    delete dut; return 0;
}
