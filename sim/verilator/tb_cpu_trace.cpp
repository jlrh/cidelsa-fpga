// ============================================================================
//  tb_cpu_trace — valida la CPU 1802 + sistema contra el oráculo de I/O de MAME.
//  Ejecuta cidelsa_machine desde reset y registra las primeras N operaciones OUT
//  (puerto, dato, dirección R(X)) → dumps/io_trace_sim.txt para comparar con
//  dumps/io_trace_mame.txt.
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
    int N = (argc>1)? atoi(argv[1]) : 60;

    dut->ce_cpu=1; dut->in0=0xff; dut->in1=0xff; dut->ef=0; dut->int_req=0; dut->clk=0;
    dut->reset=1; dut->eval(); for(int i=0;i<8;i++) tick(); dut->reset=0;

    FILE* f=fopen("../../debug/destryer/dumps/io_trace_sim.txt","w");
    int prev_out=0, cnt=0, prev_fetch=0; long cyc=0, last_out_cyc=0;
    // anillo de últimos PCs de fetch
    uint16_t pcring[64]; int pri=0;
    while(cnt<N && cyc<100000000L){
        int prd_lo = (cyc % 71580) > 65000;
        dut->ef = prd_lo ? 0x1 : 0x0; dut->int_req = prd_lo ? 1 : 0;
        tick(); cyc++;
        static FILE* spf=fopen("../../debug/destryer/dumps/pc_trace_sim.txt","w");
        static int snf=0;
        if(dut->dbg_fetch && !prev_fetch){
            uint16_t pc=dut->dbg_pc;
            pcring[pri++ & 63]=pc;
            if(spf && snf<6000){ fprintf(spf,"%04x\n",pc); if(++snf==6000) fclose(spf); }
            static int r11n=0; if(pc==0x00e1 && cnt>=12 && r11n<14){ printf("  [post-OUT12] 0xe1: R11=0x%04x\n", dut->dbg_rb); r11n++; }
            static int last=0; if((pc>=0x2000&&pc<0xf400) && !last){ last=1; printf(">>> RUNAWAY a pc=0x%04x; PCs previos: ",pc); for(int k=2;k<18;k++) printf("%04x ",pcring[(pri-18+k)&63]); printf("\n"); }
        }
        prev_fetch = dut->dbg_fetch;
        int out_now = dut->io_active && dut->io_is_out;
        if(out_now && !prev_out){
            cnt++; last_out_cyc=cyc;
            fprintf(f,"%d port=%d data=0x%02x rx=0x%04x\n", cnt, dut->io_port, dut->io_data, dut->io_addr);
            if(cnt<=8) printf("  SIM OUT#%d port=%d data=0x%02x rx=0x%04x\n", cnt, dut->io_port, dut->io_data, dut->io_addr);
        }
        prev_out = out_now;
        // si lleva mucho sin un OUT nuevo, volcar el bucle de PCs y salir
        if(cyc - last_out_cyc > 8000000){
            printf("ATASCADO tras OUT#%d. Ultimos PCs de fetch:\n  ", cnt);
            for(int k=0;k<32;k++) printf("%04x ", pcring[(pri+32+k)&63]);
            printf("\n"); break;
        }
    }
    fclose(f);
    printf(">>> %d OUTs en %ld ciclos -> io_trace_sim.txt\n", cnt, cyc);
    delete dut; return 0;
}
