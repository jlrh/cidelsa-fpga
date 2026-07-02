// ============================================================================
//  tb_charsweep — corre el sistema vivo y, en un rango de frames, vuelca el
//  estado de los glifos redefinibles char 0xbe (idx 0x5f0..0x5f7) y char 0xff
//  (idx 0x7f8..0x7ff). Objetivo: demostrar que la divergencia vs MAME en esos
//  dos códigos es FASE DE ANIMACION (timing), no direccionamiento: si en algún
//  frame char[0xff] queda todo-00 (== dump MAME), queda probado.
//  Ratio de reloj = cristales exactos de MAME (3.579 / 5.7143 MHz).
//  uso: tb_charsweep [f_ini] [f_fin]
// ============================================================================
#include "Vcidelsa_machine.h"
#include "Vcidelsa_machine___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vcidelsa_machine* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

int main(int argc, char** argv){
    Verilated::commandArgs(argc, argv);
    dut = new Vcidelsa_machine;
    int FINI = (argc>1)? atoi(argv[1]) : 980;
    int FFIN = (argc>2)? atoi(argv[2]) : 1020;

    dut->in0=0xff; dut->in1=0xff; dut->ef_ext=0; dut->clk=0;
    dut->ce_cpu=0; dut->ce_pix=0; dut->reset=1; dut->eval();
    for(int i=0;i<8;i++){ dut->ce_cpu=1; dut->ce_pix=1; tick(); }
    dut->reset=0;

    long acc=0, frames=0;
    int pv=1, ph=1;
    auto rp = dut->rootp;
    long maxticks = (long)FFIN*120000 + 400000;
    for(long t=0; t<maxticks && frames<=FFIN; t++){
        dut->ce_pix = 1;
        // ratio de cristal exacto MAME: 3.579 MHz CPU / 5.7143 MHz dot
        acc += 3579000; int cce=0; if(acc >= 5714300){ acc -= 5714300; cce=1; }
        dut->ce_cpu = cce;
        tick();
        if(dut->hcount==0 && dut->vcount==0 && (ph||pv)){
            frames++;
            if(frames>=FINI && frames<=FFIN){
                printf("f=%4ld  0xbe[", frames);
                for(int i=0;i<8;i++) printf("%02x", rp->cidelsa_machine__DOT__u_vram__DOT__char_mem[0x5f0+i]);
                printf("]  0xff[");
                int allzero=1;
                for(int i=0;i<8;i++){ uint8_t v=rp->cidelsa_machine__DOT__u_vram__DOT__char_mem[0x7f8+i]; printf("%02x", v); if(v) allzero=0; }
                printf("]%s\n", allzero? "  <-- 0xff TODO-00 (==MAME)":"");
            }
        }
        ph = dut->hcount; pv = dut->vcount;
    }
    delete dut; return 0;
}
