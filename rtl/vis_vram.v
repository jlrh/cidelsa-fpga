// ============================================================================
//  vis_vram — Memorias de vídeo del VIS: PAGE / CHAR / PCB RAM
// ----------------------------------------------------------------------------
//  Bloque 2.  PAGE RAM 1K×8, CHAR RAM 2K×8, PCB RAM 2K×1.
//
//  VERSIÓN SINTETIZABLE (MiSTer/Cyclone V) — arrays DUPLICADOS por dominio de
//  lectura para que cada uno infiera el recurso adecuado sin conflicto:
//   - Copia de VÍDEO  (*_v): lectura SÍNCRONA REGISTRADA (gatada por ce_pix) →
//     se infiere como BRAM M10K (1 dot de latencia). vis_video está pipelined
//     para casar con esta latencia (replay sim==golden==MAME 0.00%).
//   - Copia de CPU    (*_c, nombres page_mem/char_mem/pcb_mem): lectura
//     COMBINACIONAL (la usa el direccionamiento de escritura de char y el bus del
//     1802 en cidelsa_machine) → se infiere como LUTRAM/MLAB (async-read OK en
//     Cyclone V). Mantiene el sistema vivo EXACTO (2635 OUTs ==MAME) sin tocar
//     cidelsa_machine.
//   - ESCRITURA de CPU: síncrona, actualiza AMBAS copias con el mismo dato.
//
//  Direccionamiento (igual que reference/mame/cidelsa_v.cpp):
//    CHAR/PCB: addr = ((column<<3) | (cma&7)) & 0x7ff   (lo calcula vis_video)
//    PAGE:     addr = pma & 0x3ff (Cidelsa; 0x7ff si dblpage)
//
//  REPLAY: con `define REPLAY se precargan AMBAS copias desde los volcados de
//  MAME (debug/destryer/dumps/*.hex), para validar sim==golden.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

// La copia de VÍDEO (*_v) es de lectura REGISTRADA (BRAM M10K). La copia de CPU es de
// lectura ASÍNCRONA (el bus del 1802 / direccionamiento de write la usan combinacional;
// VALIDADO que registrarla rompe el CPU). En Cyclone V la copia de CPU se mapea a
// LUTRAM/MLAB (async-read) vía ramstyle="MLAB".

module vis_vram (
    input  wire        clk,
    input  wire        ce_pix,        // enable del dot clock (latencia de lectura de vídeo)

    // --- lectura de vídeo (SÍNCRONA registrada, gatada por ce_pix) ---
    input  wire [10:0] page_addr,   // 11 bits (mask externo a 0x3ff/0x7ff)
    output reg  [7:0]  page_q,
    input  wire [10:0] char_addr,
    output reg  [7:0]  char_q,
    input  wire [10:0] pcb_addr,
    output reg         pcb_q,

    // --- lectura de la CPU (REGISTRADA en clk libre → M10K): page (tb pmd del char) + char ---
    input  wire [10:0] cpu_prd_addr,  output reg  [7:0] cpu_prd_q,   // CPU page read
    input  wire [10:0] cpu_crd_addr,  output reg  [7:0] cpu_crd_q,   // CPU char read
    input  wire [10:0] cpu_pcbrd_addr, output reg       cpu_pcbrd_q, // CPU pcb read (IN0[7])

    // --- escritura de la CPU (síncrona; actualiza ambas copias) ---
    input  wire        cpu_page_we, input wire [10:0] cpu_page_addr, input wire [7:0] cpu_page_d,
    input  wire        cpu_char_we, input wire [10:0] cpu_char_addr, input wire [7:0] cpu_char_d,
    input  wire        cpu_pcb_we,  input wire [10:0] cpu_pcb_addr,  input wire       cpu_pcb_d
);
    // ---- copia de CPU (lectura REGISTRADA → BRAM M10K). Nombres "clásicos" para los
    //      taps de los testbench (verilator public_flat_rd). Es la copia "maestra". ----
    // PAGE RAM 2KB: Cidelsa usa 1KB (la lectura llega con bit10=0); Draco usa los 2KB.
    (* ramstyle = "M10K" *) reg [7:0] page_mem [0:2047] /*verilator public_flat_rd*/;
    (* ramstyle = "M10K" *) reg [7:0] char_mem [0:2047] /*verilator public_flat_rd*/;
    (* ramstyle = "M10K" *) reg       pcb_mem  [0:2047] /*verilator public_flat_rd*/;
    // ---- copia de VÍDEO (registered-read → BRAM M10K) ----
    reg [7:0] page_mem_v [0:2047];
    reg [7:0] char_mem_v [0:2047];
    reg       pcb_mem_v  [0:2047];

    // ---- lectura de vídeo: registrada en ce_pix (BRAM con output-register) ----
    always @(posedge clk) begin
        if (ce_pix) begin
            page_q <= page_mem_v[page_addr[10:0]];
            char_q <= char_mem_v[char_addr];
            pcb_q  <= pcb_mem_v [pcb_addr];
        end
    end

    // ---- lectura de CPU: REGISTRADA en clk LIBRE (1 dot de latencia → infiere M10K).
    //  El 1802 presenta `address` (= función PURA de registros, estable todo el paso de ce)
    //  y consume data_in en el borde de ce_cpu. Con clk≫ce_cpu (en HW ~8 clk/paso) la lectura
    //  registrada llega válida a tiempo. VALIDADO con cadencia HW (tb_outtrace_slow). ----
`ifdef MEM_ASYNC
    // A/B test: lectura ASÍNCRONA combinacional (config validada-live original).
    always @(*) begin
        cpu_prd_q   = page_mem[cpu_prd_addr[10:0]];
        cpu_crd_q   = char_mem[cpu_crd_addr];
        cpu_pcbrd_q = pcb_mem [cpu_pcbrd_addr];
    end
`else
    always @(posedge clk) begin
        cpu_prd_q   <= page_mem[cpu_prd_addr[10:0]];   // 2KB (Draco); Destroyer no lee bit10
        cpu_crd_q   <= char_mem[cpu_crd_addr];
        cpu_pcbrd_q <= pcb_mem [cpu_pcbrd_addr];
    end
`endif

    // ---- escritura de CPU: ambas copias con el mismo dato ----
    always @(posedge clk) begin
        if (cpu_page_we) begin page_mem[cpu_page_addr[10:0]] <= cpu_page_d; page_mem_v[cpu_page_addr[10:0]] <= cpu_page_d; end  // 2KB (Draco)
        if (cpu_char_we) begin char_mem[cpu_char_addr]      <= cpu_char_d; char_mem_v[cpu_char_addr]      <= cpu_char_d; end
        if (cpu_pcb_we)  begin pcb_mem [cpu_pcb_addr]       <= cpu_pcb_d;  pcb_mem_v [cpu_pcb_addr]       <= cpu_pcb_d;  end
    end

`ifdef REPLAY
    // Escena de replay parametrizable: el driver copia la escena a replay_scene/.
    // (Para la tabla histórica, copiar dumps/ a replay_scene/.)
    integer ri;
    initial begin
        $readmemh("../../debug/destryer/replay_scene/page_ram.hex", page_mem);
        $readmemh("../../debug/destryer/replay_scene/char_ram.hex", char_mem);
        $readmemh("../../debug/destryer/replay_scene/pcb_ram.hex",  pcb_mem);
        for (ri=0; ri<2048; ri=ri+1) page_mem_v[ri] = page_mem[ri];   // page 2KB (Draco)
        for (ri=0; ri<2048; ri=ri+1) char_mem_v[ri] = char_mem[ri];
        for (ri=0; ri<2048; ri=ri+1) pcb_mem_v[ri]  = pcb_mem[ri];
    end
`endif
endmodule

`default_nettype wire
