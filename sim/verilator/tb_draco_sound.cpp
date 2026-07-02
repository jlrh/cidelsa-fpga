// tb_draco_sound — comprueba la integración COP402+AY (jt49): mete un comando de
// sonido y verifica que el AY recibe escrituras (G/Q) y que sale audio.
#include "Vdraco_sound.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vdraco_sound* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

int main(int argc, char** argv){
    Verilated::commandArgs(argc, argv);
    dut = new Vdraco_sound;
    long INSTR = (argc>1)? atol(argv[1]) : 60000;

    dut->sndcmd = 0;            // sin comando
    dut->ce_cop=0; dut->ce_ay=0; dut->clk=0; dut->reset=1; dut->eval();
    for(int i=0;i<40;i++){ dut->ce_ay=1; dut->ce_cop=1; tick(); }
    dut->reset=0;

    // ce_ay cada clk; ce_cop cada 16 clks (COP402 = CKI/16, AY = CKI)
    long cop_instr=0, ay_writes=0, last_g=0; int aud_nz=0;
    long clks=0, sent_at=0;
    while(cop_instr < INSTR){
        dut->ce_ay = 1;
        dut->ce_cop = (clks % 16 == 0) ? 1 : 0;
        if(dut->ce_cop) cop_instr++;
        // a mitad: enviar comando de sonido 1
        if(cop_instr==30000 && !sent_at){ dut->sndcmd=1; sent_at=cop_instr; printf("    [%ld] sndcmd=1\n",cop_instr); }
        tick();
        // detectar escrituras al AY (G=3 latch / G=1 write)
        if((dut->dbg_cop_g==3 || dut->dbg_cop_g==1) && dut->dbg_cop_g!=last_g) ay_writes++;
        last_g = dut->dbg_cop_g;
        if(dut->audio != 0) aud_nz++;
        clks++;
    }
    printf(">>> %ld instr COP402, %ld transiciones de escritura AY, audio!=0 en %d clks\n",
        cop_instr, ay_writes, aud_nz);
    delete dut; return 0;
}
