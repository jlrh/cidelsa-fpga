// ============================================================================
//  tb_outtrace_draco — corre draco_machine vivo y vuelca TODAS las OUTs
//  (port,data,rx,pc) hasta N, para comparar con io_trace_draco_mame.txt.
//  Ratio de cristal Draco: CPU 4.43361 MHz / dot 5.626 MHz (PAL).
//  Inputs idle = los defaults de MAME (in1 = DIPs por defecto = 0xd6).
//  uso: tb_outtrace_draco [N]
// ============================================================================
#include "Vdraco_machine.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vdraco_machine* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

int main(int argc, char** argv){
    Verilated::commandArgs(argc, argv);
    dut = new Vdraco_machine;
    long N = (argc>1)? atol(argv[1]) : 3000;

    dut->in0=0x7f;          // botones active-low sin pulsar (b7=PCB lo pone el RTL)
    dut->in1=0xd6;          // DIPs default Draco (Diff 0x02|Bonus 0x04|Lives 0x10|Coin 0xc0)
    dut->in2=0xff;          // joysticks neutrales (active-low)
    dut->ef_ext=0;          // service/coin no pulsados
    dut->ioctl_rom_we=0; dut->ioctl_rom_addr=0; dut->ioctl_rom_data=0;
    dut->clk=0; dut->ce_cpu=0; dut->ce_pix=0; dut->ce_cop=0; dut->ce_ay=0;
    dut->reset=1; dut->eval();
    for(int i=0;i<8;i++){ dut->ce_cpu=1; dut->ce_pix=1; tick(); }
    dut->reset=0;

    long acc=0, outs=0; int prevout=0; long copdiv=0;
    FILE* ft=fopen("../../debug/destryer/dumps/io_trace_draco_live.txt","w");
    long maxticks = 200000000L;
    for(long t=0; t<maxticks && outs<N; t++){
        dut->ce_pix = 1;
        acc += 4433610; int cce=0; if(acc >= 5626000){ acc -= 5626000; cce=1; }
        dut->ce_cpu = cce;
        dut->ce_ay  = 1;
        dut->ce_cop = (copdiv % 16 == 0) ? 1 : 0; copdiv++;
        tick();
        int outnow = dut->io_active && dut->io_is_out;
        if(outnow && !prevout){
            outs++;
            fprintf(ft,"%ld port=%d data=0x%02x rx=0x%04x pc=0x%04x\n",
                outs, dut->io_port, dut->io_data, dut->io_addr, dut->dbg_pc);
        }
        prevout = outnow;
    }
    fclose(ft);
    printf(">>> %ld OUTs -> io_trace_draco_live.txt\n", outs);
    delete dut; return 0;
}
