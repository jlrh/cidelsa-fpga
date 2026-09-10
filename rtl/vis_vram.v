`timescale 1ns/1ps
`default_nettype none

module vis_vram (
    input  wire        clk,
    input  wire        ce_pix,

    input  wire [10:0] page_addr,
    output reg  [7:0]  page_q,
    input  wire [10:0] char_addr,
    output reg  [7:0]  char_q,
    input  wire [10:0] pcb_addr,
    output reg         pcb_q,

    input  wire [10:0] cpu_prd_addr,  output reg  [7:0] cpu_prd_q,
    input  wire [10:0] cpu_crd_addr,  output reg  [7:0] cpu_crd_q,
    input  wire [10:0] cpu_pcbrd_addr, output reg       cpu_pcbrd_q,

    input  wire        cpu_page_we, input wire [10:0] cpu_page_addr, input wire [7:0] cpu_page_d,
    input  wire        cpu_char_we, input wire [10:0] cpu_char_addr, input wire [7:0] cpu_char_d,
    input  wire        cpu_pcb_we,  input wire [10:0] cpu_pcb_addr,  input wire       cpu_pcb_d
);

    (* ramstyle = "M10K" *) reg [7:0] page_mem [0:2047] /*verilator public_flat_rd*/;
    (* ramstyle = "M10K" *) reg [7:0] char_mem [0:2047] /*verilator public_flat_rd*/;
    (* ramstyle = "M10K" *) reg       pcb_mem  [0:2047] /*verilator public_flat_rd*/;

    reg [7:0] page_mem_v [0:2047];
    reg [7:0] char_mem_v [0:2047];
    reg       pcb_mem_v  [0:2047];

    always @(posedge clk) begin
        if (ce_pix) begin
            page_q <= page_mem_v[page_addr[10:0]];
            char_q <= char_mem_v[char_addr];
            pcb_q  <= pcb_mem_v [pcb_addr];
        end
    end

`ifdef MEM_ASYNC

    always @(*) begin
        cpu_prd_q   = page_mem[cpu_prd_addr[10:0]];
        cpu_crd_q   = char_mem[cpu_crd_addr];
        cpu_pcbrd_q = pcb_mem [cpu_pcbrd_addr];
    end
`else
    always @(posedge clk) begin
        cpu_prd_q   <= page_mem[cpu_prd_addr[10:0]];
        cpu_crd_q   <= char_mem[cpu_crd_addr];
        cpu_pcbrd_q <= pcb_mem [cpu_pcbrd_addr];
    end
`endif

    always @(posedge clk) begin
        if (cpu_page_we) begin page_mem[cpu_page_addr[10:0]] <= cpu_page_d; page_mem_v[cpu_page_addr[10:0]] <= cpu_page_d; end
        if (cpu_char_we) begin char_mem[cpu_char_addr]      <= cpu_char_d; char_mem_v[cpu_char_addr]      <= cpu_char_d; end
        if (cpu_pcb_we)  begin pcb_mem [cpu_pcb_addr]       <= cpu_pcb_d;  pcb_mem_v [cpu_pcb_addr]       <= cpu_pcb_d;  end
    end

`ifdef REPLAY

    integer ri;
    initial begin
        $readmemh("../../debug/destryer/replay_scene/page_ram.hex", page_mem);
        $readmemh("../../debug/destryer/replay_scene/char_ram.hex", char_mem);
        $readmemh("../../debug/destryer/replay_scene/pcb_ram.hex",  pcb_mem);
        for (ri=0; ri<2048; ri=ri+1) page_mem_v[ri] = page_mem[ri];
        for (ri=0; ri<2048; ri=ri+1) char_mem_v[ri] = char_mem[ri];
        for (ri=0; ri<2048; ri=ri+1) pcb_mem_v[ri]  = pcb_mem[ri];
    end
`endif
endmodule

`default_nettype wire
