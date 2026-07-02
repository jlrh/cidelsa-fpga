// ============================================================================
//  tb_regs — harness Verilator AUTOVERIFICABLE del bloque 1 (vis_regs).
// ----------------------------------------------------------------------------
//  Escribe patrones a OUT3..OUT7 y comprueba el decode de cada campo contra la
//  semántica de cdp1869.cpp. OUT3 usa cpu_data; OUT4..7 usan cpu_addr.
// ============================================================================
#include "Vvis_regs.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vvis_regs* dut;
static int fails = 0;

static void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); }

static void write_reg(int n, uint8_t data, uint16_t addr) {
    dut->reg_wr = 1; dut->reg_n = n; dut->cpu_data = data; dut->cpu_addr = addr;
    tick();
    dut->reg_wr = 0; dut->eval();
}

static void chk(const char* name, long got, long exp) {
    bool ok = (got == exp);
    printf("  [%s] %-18s got=0x%lx exp=0x%lx\n", ok?"PASS":"FAIL", name, got, exp);
    if (!ok) fails++;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vvis_regs;
    dut->reg_wr = 0; dut->clk = 0;
    dut->reset = 1; tick(); tick(); dut->reset = 0; dut->eval();

    printf("Bloque 1 — vis_regs:\n");

    // --- OUT3 (data) : bkg=5, cfc=1, dispoff=0, col=2, freshorz=1 ---
    //  bits: [2:0]=101 [3]=1 [4]=0 [6:5]=10 [7]=1  => 0b1100_1101 = 0xCD
    write_reg(3, 0xCD, 0x0000);
    chk("out3.bkg",      dut->bkg, 5);
    chk("out3.cfc",      dut->cfc, 1);
    chk("out3.dispoff",  dut->dispoff, 0);
    chk("out3.col",      dut->col, 2);
    chk("out3.freshorz", dut->freshorz, 1);

    // --- OUT4 (addr) : toneamp=0xA, tonefreq=5, toneoff=1, tonediv=0x3C ---
    //  [3:0]=1010 [6:4]=101 [7]=1 [14:8]=0111100  => 0x3C00 | 0xDA = 0x3CDA
    write_reg(4, 0x00, 0x3CDA);
    chk("out4.toneamp",  dut->toneamp, 0xA);
    chk("out4.tonefreq", dut->tonefreq, 5);
    chk("out4.toneoff",  dut->toneoff, 1);
    chk("out4.tonediv",  dut->tonediv, 0x3C);

    // --- OUT5 (addr) : cmem=1, line9=1, line16=1, dblpage=1, fresvert=1,
    //                   wnamp=0xB, wnfreq=6, wnoff=1; y pma=addr[10:0] (cmem=1) ---
    //  [0]=1 [3]=1 [5]=1 [6]=1 [7]=1 [11:8]=1011 [14:12]=110 [15]=1
    //  = 1 |8 |0x20 |0x40 |0x80 |0xB00 |0x6000 |0x8000 = 0xEBE9
    write_reg(5, 0x00, 0xEBE9);
    chk("out5.cmem",     dut->cmem, 1);
    chk("out5.line9",    dut->line9, 1);
    chk("out5.line16",   dut->line16, 1);
    chk("out5.dblpage",  dut->dblpage, 1);
    chk("out5.fresvert", dut->fresvert, 1);
    chk("out5.wnamp",    dut->wnamp, 0xB);
    chk("out5.wnfreq",   dut->wnfreq, 6);
    chk("out5.wnoff",    dut->wnoff, 1);
    chk("out5.pma(cmem)", dut->pma, 0xEBE9 & 0x7FF);   // = 0x3E9

    // --- OUT5 con cmem=0 : pma debe quedar a 0 ---
    write_reg(5, 0x00, 0x07FE);  // bit0=0
    chk("out5.cmem0",    dut->cmem, 0);
    chk("out5.pma(=0)",  dut->pma, 0);

    // --- OUT6 (addr) : pma = addr & 0x7ff ---
    write_reg(6, 0x00, 0xFAB5);
    chk("out6.pma",      dut->pma, 0xFAB5 & 0x7FF);     // = 0x2B5

    // --- OUT7 (addr) : hma = addr & 0x7fc ---
    write_reg(7, 0x00, 0xFABF);
    chk("out7.hma",      dut->hma, 0xFABF & 0x7FC);     // = 0x2BC

    printf(fails ? "\n>>> %d FALLO(S)\n" : "\n>>> TODO OK\n", fails);
    delete dut;
    return fails ? 1 : 0;
}
