// ============================================================================
//  tb_outtrace_slow — como tb_outtrace pero con cadencia REALISTA de HW:
//  clk libre (1 tick = 1 clk) y ce_pix/ce_cpu generados con HUECO (clk >> ce),
//  igual que en la placa (clk_sys=30 MHz → ce_pix~5.3 clks, ce_cpu~8.4 clks).
//  Sirve para VALIDAR la ruta de memoria REGISTRADA (build con -DFORCE_MEM_SYNC):
//  si da los mismos 2635 OUTs que MAME, la lectura registrada (BRAM) es correcta.
//  uso: tb_outtrace_slow [N]
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

    dut->in0=0xff; dut->in1=0xd6; dut->ef_ext=0; dut->clk=0;
    dut->ce_cpu=0; dut->ce_pix=0; dut->reset=1; dut->eval();
    for(int i=0;i<40;i++){ dut->ce_cpu=1; dut->ce_pix=1; tick(); }
    dut->reset=0;

    long acc_pix=0, acc_cpu=0, outs=0;
    int prevout=0;
    // Valores del bus retenidos durante la EXEC del OUT. Con memoria REGISTRADA, mem_q
    // se asienta 1 clk DESPUÉS de empezar la EXEC; el HW latcha el OUT al CERRAR la EXEC
    // (flanco de ce_cpu con reg_wr). Por eso muestreamos al caer io_is_out, con el valor
    // estable (= lo que latcha el HW), no en el flanco de subida.
    int h_port=0; unsigned h_data=0, h_pc=0, h_addr=0, h_r1=0, h_p=0, h_x=0;
    FILE* ft=fopen("../../debug/destryer/dumps/io_trace_live_full.txt","w");
    long maxticks = 2000000000L;
    for(long t=0; t<maxticks && outs<N; t++){
        // cadencia HW: clk_sys=30 MHz. ce_cpu = CICLO DE MÁQUINA = reloj_1802/8 = 3.579/8 = 447 kHz.
        //  ce_pix: 5.626 (HW real) o 5714 (=MAME, para comparar con el oráculo) si MAME_CLK.
        static int PIXK = getenv("MAME_CLK") ? 5714 : 5626;
        acc_pix += PIXK; int cpx=0; if(acc_pix >= 30000){ acc_pix -= 30000; cpx=1; }
        acc_cpu += 447;  int ccp=0; if(acc_cpu >= 30000){ acc_cpu -= 30000; ccp=1; }
        dut->ce_pix = cpx; dut->ce_cpu = ccp;
        tick();
        if(getenv("DBG") && t<200) printf("t=%ld ce=%d st=%d op=%02x addr=%04x memq=%02x pc=%04x isout=%d\n",
            t, ccp, dut->dbg_state, dut->dbg_op, dut->io_addr, dut->io_data, dut->dbg_pc, dut->io_is_out);
        // log de CADA cambio de R1 con pc/op/D, en la ventana de divergencia
        static unsigned pr1=0xffff;
        if(outs>=1955 && outs<=1985 && dut->dbg_r1!=pr1){
            printf("R1: %04x->%04x pc=%04x op=%02x D=%02x P=%d X=%d (out=%ld)\n",
                pr1, dut->dbg_r1, dut->dbg_pc, dut->dbg_op, dut->dbg_d_out, dut->dbg_p, dut->dbg_x, outs);
            pr1=dut->dbg_r1;
        }
        int outnow = dut->io_is_out;
        if(outnow){ h_port=dut->io_port; h_data=dut->io_data; h_pc=dut->dbg_pc; h_addr=dut->io_addr;
                    h_r1=dut->dbg_r1; h_p=dut->dbg_p; h_x=dut->dbg_x; }
        if(prevout && !outnow){          // OUT completado: latch como el HW (fin de EXEC)
            outs++;
            fprintf(ft,"%ld port=%d data=0x%02x pc=0x%04x R0=0x%04x R1=0x%04x P=%d X=%d\n",
                outs, h_port, h_data, h_pc, h_addr, h_r1, h_p, h_x);
        }
        prevout = outnow;
    }
    fclose(ft);
    printf(">>> %ld OUTs (cadencia HW clk>>ce) -> io_trace_live_full.txt\n", outs);
    delete dut; return 0;
}
