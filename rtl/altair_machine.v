// ============================================================================
//  altair_machine — Sistema Altair COMPLETO (CPU 1802 + VIS + memoria + I/O)
// ----------------------------------------------------------------------------
//  Igual que cidelsa_machine (Destroyer: vídeo Cidelsa draco=0, addressing 1869
//  CHAR/PAGE por column/0xff) pero con el mapa de Altair (reference/mame/cidelsa.cpp):
//    ROM 0x0000-0x2FFF (12K) | NVRAM 0x3000-0x30FF | CHAR 0xF400-F7FF | PAGE 0xF800-FFFF
//  I/O vía CDP1852 (ports 1/2/4):  INP1=IN0(ic23) INP2=IN1(ic24,DIPs) INP4=IN2(ic25)
//    OUT1→ic26 (LEDs/contadores, no afecta CPU) ; OUT3-7 = registros 1869.
//  EF1 = ~PRD.  IN0 bit7 = PCB (cdp1869_pcb_r), igual que Destroyer.
//  Creado para REGRESIÓN del CPU tras el fix SHRC/SHLC (opcodes 0x76/0x7E).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module altair_machine (
    input  wire        clk,
    input  wire        ce_cpu,
    input  wire        ce_pix,
    input  wire        reset,

    input  wire [7:0]  in0,         // IN0 (controles; bit7 = PCB, lo pone el HW)
    input  wire [7:0]  in1,         // IN1 (DIPs)
    input  wire [7:0]  in2,         // IN2 (joysticks up/down/button2)
    input  wire [3:0]  ef_ext,      // EF2..EF4 externos; EF1 lo pone PRD

    output wire        q_out,

    output wire [8:0]  hcount, vcount,
    output wire        hsync, vsync, de,
    output wire [7:0]  r, g, b,
    output wire signed [15:0] audio,

    // traza de I/O (debug/validación)
    output wire        io_active, io_is_out,
    output wire [2:0]  io_port,
    output wire [7:0]  io_data,
    output wire [15:0] io_addr,
    output wire [15:0] dbg_pc,
    output wire        dbg_fetch,
    output wire [15:0] dbg_rb,
    output wire [15:0] dbg_cfg,
    output wire [10:0] dbg_hma,
    output wire [2:0]  dbg_state,
    output wire [7:0]  dbg_op,
    output wire [15:0] dbg_r1,
    output wire [3:0]  dbg_p,
    output wire [3:0]  dbg_x,
    output wire [7:0]  dbg_d_out
);
    // ================= CPU =================
    wire [15:0] address;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din;
    wire        mem_read, mem_write;
    wire [2:0]  cpu_io_port;
    wire [1:0]  sc;
    wire [15:0] cpu_pc;

    wire prd_int;
    wire [3:0] ef = {ef_ext[3:1], prd_int};

    cdp1802_jl u_cpu (
        .clk(clk), .clk_enable(ce_cpu), .clear(reset),
        .dma_in_req(1'b0), .dma_out_req(1'b0), .int_req(prd_int), .wait_req(1'b0),
        .ef(ef),
        .data_in(cpu_din), .data_out(cpu_dout), .address(address),
        .mem_read(mem_read), .mem_write(mem_write),
        .io_port(cpu_io_port), .q_out(q_out), .sc(sc), .dbg_pc(cpu_pc), .dbg_r11(dbg_rb),
        .dbg_state(dbg_state), .dbg_op(dbg_op),
        .dbg_r1(dbg_r1), .dbg_p(dbg_p), .dbg_x(dbg_x), .dbg_d_out(dbg_d_out)
    );

    assign io_active = (cpu_io_port != 3'd0);
    assign io_is_out = io_active && mem_read;
    assign io_port   = cpu_io_port;
    assign io_addr   = address;
    assign dbg_fetch = (sc == 2'b00);
    assign dbg_pc    = cpu_pc;
    assign dbg_cfg   = {4'd0, dispoff, dblpage, line16, line9, fresvert, freshorz, cfc, col, bkg};
    assign dbg_hma   = hma_reg;

    // ================= registros del VIS (OUT3-7) =================
    wire reg_wr = io_active && mem_read && (cpu_io_port >= 3'd3);
    wire [2:0]  bkg; wire cfc; wire [1:0] col; wire dispoff, freshorz, fresvert;
    wire        cmem, line9, line16, dblpage; wire [3:0] wnamp; wire [2:0] wnfreq;
    wire        wnoff, toneoff; wire [3:0] toneamp; wire [2:0] tonefreq; wire [6:0] tonediv;
    wire [10:0] pma_reg, hma_reg;
    vis_regs u_regs (
        .clk(clk), .reset(reset),
        .reg_wr(reg_wr && ce_cpu), .reg_n(cpu_io_port),
        .cpu_data(io_data), .cpu_addr(address),
        .bkg(bkg), .cfc(cfc), .dispoff(dispoff), .col(col), .freshorz(freshorz),
        .toneamp(toneamp), .tonefreq(tonefreq), .toneoff(toneoff), .tonediv(tonediv),
        .cmem(cmem), .line9(line9), .line16(line16), .dblpage(dblpage), .fresvert(fresvert),
        .wnamp(wnamp), .wnfreq(wnfreq), .wnoff(wnoff),
        .pma(pma_reg), .hma(hma_reg)
    );

    // ================= VRAM compartida =================
    wire [10:0] v_page_addr, v_char_addr, v_pcb_addr;
    wire [7:0]  v_page_q, v_char_q; wire v_pcb_q;

    // Altair: mapa distinto de Destroyer (NVRAM en 0x3000, ROM 12K). Vídeo = Cidelsa.
    wire sel_rom   = (address < 16'h3000);
    wire sel_nvram = (address >= 16'h3000) && (address <= 16'h30ff);
    wire sel_char  = (address >= 16'hf400) && (address <= 16'hf7ff);
    wire sel_page  = (address >= 16'hf800);

    wire [10:0] get_pma = dblpage ? pma_reg : {1'b0, pma_reg[9:0]};
    wire [10:0] off_p  = address[10:0];
    wire [10:0] pma_p  = cmem ? get_pma : off_p;
    wire [9:0]  off_c  = address[9:0];
    wire [3:0]  cma    = dblpage ? {1'b0, off_c[2:0]} : off_c[3:0];
    wire [10:0] pma_c  = cmem ? get_pma : {1'b0, off_c};

    wire [10:0] cpu_prd_addr = sel_char ? pma_c : pma_p;
    wire [7:0]  cpu_prd_q;
    wire [7:0]  pmd_cpu   = cpu_prd_q;
    wire [7:0]  column    = pma_c[10] ? 8'hff : pmd_cpu;
    wire [10:0] char_idx  = ((column << 3) | (cma & 3'd7)) & 11'h7ff;

    wire [7:0]  cpu_crd_q;
    wire        cpu_pcbrd_q;

    vis_vram u_vram (
        .clk(clk), .ce_pix(ce_pix),
        .page_addr(v_page_addr), .page_q(v_page_q),
        .char_addr(v_char_addr), .char_q(v_char_q),
        .pcb_addr(v_pcb_addr),   .pcb_q(v_pcb_q),
        .cpu_prd_addr(cpu_prd_addr),   .cpu_prd_q(cpu_prd_q),
        .cpu_crd_addr(char_idx),       .cpu_crd_q(cpu_crd_q),
        .cpu_pcbrd_addr(char_idx),     .cpu_pcbrd_q(cpu_pcbrd_q),
        .cpu_page_we(ce_cpu && mem_write && sel_page), .cpu_page_addr(pma_p),   .cpu_page_d(cpu_dout),
        .cpu_char_we(ce_cpu && mem_write && sel_char), .cpu_char_addr(char_idx),.cpu_char_d(cpu_dout),
        .cpu_pcb_we (ce_cpu && mem_write && sel_char), .cpu_pcb_addr(char_idx), .cpu_pcb_d(q_out)
    );

    // ================= vídeo (Cidelsa, draco=0) =================
    vis_video u_video (
        .clk(clk), .reset(reset), .ce_pix(ce_pix),
        .bkg(bkg), .cfc(cfc), .col(col), .dispoff(dispoff),
        .freshorz(freshorz), .fresvert(fresvert), .line9(line9), .line16(line16),
        .dblpage(dblpage), .hma(hma_reg), .draco(1'b0),
        .page_addr(v_page_addr), .page_q(v_page_q),
        .char_addr(v_char_addr), .char_q(v_char_q),
        .pcb_addr(v_pcb_addr),   .pcb_q(v_pcb_q),
        .hcount(hcount), .vcount(vcount), .hsync(hsync), .vsync(vsync), .de(de),
        .prd_int(prd_int), .r(r), .g(g), .b(b)
    );

    // ================= sonido (CDP1869 tone/noise) =================
    vis_sound u_sound (
        .clk(clk), .reset(reset), .ce_pix(ce_pix),
        .toneamp(toneamp), .tonefreq(tonefreq), .toneoff(toneoff), .tonediv(tonediv),
        .wnamp(wnamp), .wnfreq(wnfreq), .wnoff(wnoff),
        .audio(audio)
    );

    // ================= ROM (12K) / NVRAM (0x3000) =================
    (* ramstyle = "M10K" *) reg [7:0] rom   [0:12287] /*verilator public_flat_rd*/;
    (* ramstyle = "M10K" *) reg [7:0] nvram [0:255]   /*verilator public_flat_rd*/;

    reg pcb_in0;
    always @(posedge clk) if (ce_cpu && mem_read && sel_char) pcb_in0 <= cpu_pcbrd_q;
    wire [7:0] in0_pcb = {pcb_in0, in0[6:0]};

    // I/O de Altair: INP1=IN0, INP2=IN1(DIPs), INP4=IN2
    wire [7:0] io_in = (cpu_io_port == 3'd1) ? in0_pcb :
                       (cpu_io_port == 3'd2) ? in1 :
                       (cpu_io_port == 3'd4) ? in2 : 8'hff;

    reg [7:0] rom_q, nvram_q;
`ifdef MEM_ASYNC
    always @(*) begin
        rom_q   = rom[address[13:0]];
        nvram_q = nvram[address[7:0]];
    end
`else
    always @(posedge clk) begin
        rom_q   <= rom[address[13:0]];
        nvram_q <= nvram[address[7:0]];
    end
`endif

    wire [7:0] mem_q = sel_rom   ? rom_q :
                       sel_nvram ? nvram_q :
                       sel_char  ? cpu_crd_q :
                       sel_page  ? cpu_prd_q : 8'hff;

    assign io_data = mem_q;
    always @(*) begin
        if (io_active && mem_write) cpu_din = io_in;
        else                        cpu_din = mem_q;
    end

    always @(posedge clk) begin
        if (ce_cpu && mem_write && sel_nvram) nvram[address[7:0]] <= cpu_dout;
    end

`ifdef SIM
    initial $readmemh("../../roms/altair_prog.hex", rom);
`else
    initial $readmemh("altair_prog.hex", rom);
`endif

`ifdef WRITETRACE
    always @(posedge clk) if (ce_cpu && mem_write)
        $display("W pc=%04x addr=%04x data=%02x cmem=%b dbl=%b %s",
            cpu_pc, address, cpu_dout, cmem, dblpage,
            sel_char ? "CHAR" : sel_page ? "PAGE" : sel_nvram ? "NVRAM" : "OTHER");
`endif
endmodule

`default_nettype wire
