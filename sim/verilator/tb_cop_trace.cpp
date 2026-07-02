// ============================================================================
//  tb_cop_trace — valida cop402_jl contra el oráculo de MAME.
//  Corre el COP402 (1 instrucción por ce), loga las instrucciones EJECUTADAS
//  (PC,A,B,G,Q,EN). Alimenta in_in = ~snd & 7 con la secuencia de comandos de
//  sonido del 1802 leída del oráculo (cop_trace_mame.txt col snd), para validar
//  también las ramas de GENERACIÓN de sonido (no solo el idle).
//  uso: tb_cop_trace [N]
// ============================================================================
#include "Vcop402_jl.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <vector>

static Vcop402_jl* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

int main(int argc, char** argv){
    Verilated::commandArgs(argc, argv);
    dut = new Vcop402_jl;
    long N = (argc>1)? atol(argv[1]) : 8000;

    // leer la secuencia de comandos de sonido del oráculo (col snd, 1-indexed)
    std::vector<int> snd; snd.push_back(0); // índice 0 dummy
    FILE* fm=fopen("../../debug/destryer/dumps/cop_trace_mame.txt","r");
    if(fm){ char line[256]; while(fgets(line,sizeof(line),fm)){ int s=0; char* p=strstr(line,"snd="); if(p) s=atoi(p+4); snd.push_back(s); } fclose(fm); }
    printf("    comandos de sonido leídos: %zu\n", snd.size()-1);

    dut->in_in = 7; dut->l_in = 0;
    dut->ce=0; dut->clk=0; dut->reset=1; dut->eval();
    for(int i=0;i<4;i++) tick();
    dut->reset=0;

    FILE* ft=fopen("../../debug/destryer/dumps/cop_trace_sim.txt","w");
    long cnt=0, guard=0;
    while(cnt<N && guard<4000000){
        dut->ce=1; dut->eval();
        if(!dut->dbg_skip){
            cnt++;
            int s = (cnt < (long)snd.size()) ? snd[cnt] : 0;
            dut->in_in = (~s) & 7;     // comando para esta instrucción
            dut->eval();
            fprintf(ft,"%ld pc=%03x A=%x B=%02x G=%x Q=%02x EN=%x snd=%d\n",
                cnt, dut->dbg_pc & 0x3ff, dut->dbg_a & 0xf, dut->dbg_b & 0x3f,
                dut->dbg_g & 0xf, dut->dbg_q & 0xff, dut->dbg_en & 0xf, s);
        }
        tick();
        guard++;
    }
    fclose(ft);
    printf(">>> %ld instrucciones -> cop_trace_sim.txt\n", cnt);
    delete dut; return 0;
}
