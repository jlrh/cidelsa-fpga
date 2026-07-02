// ============================================================================
//  draco_machine — Sistema DRACO COMPLETO (CPU 1802 + VIS + sonido COP402/AY + I/O)
// ----------------------------------------------------------------------------
//  Análogo a cidelsa_machine pero para DRACO (3er juego del VIDEO SYSTEM-1):
//   - Mapa: 0x0000-3FFF ROM(16K) | 0x8000-83FF RAM/NVRAM(1K) | 0xF400-F7FF CHAR |
//           0xF800-FFFF PAGE(2K).
//   - VIS en modo Draco (vis_video .draco(1)): direccionamiento CHAR por pmd
//     directo (sin el truco column=0xff de Cidelsa) y PAGE de 2KB.
//   - I/O: INP1=IN0(ic29) / OUT1=sonido(out1 bits5-7) ; INP2=IN1(ic30, DIPs) ;
//          INP4=IN2(ic31, joysticks) ; OUT3-7 = registros del 1869.
//   - Sonido: draco_sound = COP402 + AY-3-8910 (jt49), comando = out1[7:5].
//   - EF1/INT = ~PRD (vblank); EF2..4 = service/coin externos. Q -> PCB.
//
//  Relojes (un clk + ce): ce_cpu (DRACO_CHR1 4.43361 MHz), ce_pix (dot 5.626 PAL),
//  ce_cop (COP402 CKI/16 ~125.76kHz), ce_ay (AY CKI 2.012160 MHz).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

// Memoria del bus de CPU = lectura ASÍNCRONA (el CDP1802 lee y usa en el mismo
// ciclo; registrarla rompe el CPU — VALIDADO). En Cyclone V → LUTRAM/MLAB.

module draco_machine (
    input  wire        clk,
    input  wire        ce_cpu,
    input  wire        ce_pix,
    input  wire        ce_cop,      // enable de instrucción del COP402 (CKI/16)
    input  wire        ce_ay,       // enable del reloj del AY-3-8910 (CKI)
    input  wire        reset,

    input  wire [7:0]  in0,         // IN0 (ic29): b0=Start1 b1=Start2 b2=Tilt … b7=PCB(lo pone el HW)
    input  wire [7:0]  in1,         // IN1 (ic30): DIPs (Difficulty/Bonus/Lives/Coinage)
    input  wire [7:0]  in2,         // IN2 (ic31): joysticks (P1 b0-3, P2 b4-7)
    input  wire [3:0]  ef_ext,      // EF2..EF4 (service/coin) en bits[3:1]; EF1 lo pone PRD

    // --- carga de ROM por HPS (MiSTer ioctl) ---
    input  wire        ioctl_rom_we,
    input  wire [13:0] ioctl_rom_addr,
    input  wire [7:0]  ioctl_rom_data,

    output wire        q_out,

    // --- vídeo ---
    output wire [8:0]  hcount, vcount,
    output wire        hsync, vsync, de,
    output wire [7:0]  r, g, b,

    // --- audio (mezcla del AY) ---
    output wire signed [15:0] audio,

    // --- traza de I/O (debug/validación) ---
    output wire        io_active, io_is_out,
    output wire [2:0]  io_port,
    output wire [7:0]  io_data,
    output wire [15:0] io_addr,
    output wire [15:0] dbg_pc,
    output wire        dbg_fetch,
    output wire [15:0] dbg_rb,
    output wire [2:0]  dbg_sndcmd
);
    // ================= CPU =================
    wire [15:0] address;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din;
    wire        mem_read, mem_write;
    wire [2:0]  cpu_io_port;
    wire [1:0]  sc;
    wire [15:0] cpu_pc;

    // DRACO: PRD del 1869 va a EF1 (NO al INT) — cidelsa_v.cpp:191 prd_callback→set_inputline(EF1).
    // Además EF1 = PRD SIN invertir (port "CDP1869 PRD, pushed", cidelsa.cpp:352), = ~prd_int.
    // (Destroyer/Altair: PRD→INT invertido + EF1 invertido). Draco NO usa interrupciones del 1802.
    wire prd_int;
    wire [3:0] ef = {ef_ext[3:1], ~prd_int};

    cdp1802_jl u_cpu (
        .clk(clk), .clk_enable(ce_cpu), .clear(reset),
        .dma_in_req(1'b0), .dma_out_req(1'b0), .int_req(1'b0), .wait_req(1'b0),
        .ef(ef),
        .data_in(cpu_din), .data_out(cpu_dout), .address(address),
        .mem_read(mem_read), .mem_write(mem_write),
        .io_port(cpu_io_port), .q_out(q_out), .sc(sc), .dbg_pc(cpu_pc), .dbg_r11(dbg_rb)
    );

    assign io_active = (cpu_io_port != 3'd0);
    assign io_is_out = io_active && mem_read;
    assign io_port   = cpu_io_port;
    assign io_addr   = address;
    assign dbg_fetch = (sc == 2'b00);
    assign dbg_pc    = cpu_pc;

    // ================= registros del VIS (OUT3-7) =================
    wire reg_wr = io_active && mem_read && (cpu_io_port >= 3'd3);  // OUT3..7
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

    // --- mapa de DRACO ---
    wire sel_rom  = (address < 16'h4000);                          // ROM 16K
    wire sel_ram  = (address >= 16'h8000) && (address <= 16'h83ff);// RAM/NVRAM 1K
    wire sel_char = (address >= 16'hf400) && (address <= 16'hf7ff);
    wire sel_page = (address >= 16'hf800);

    // get_pma(): dblpage ? pma_reg : pma_reg & 0x3ff
    wire [10:0] get_pma = dblpage ? pma_reg : {1'b0, pma_reg[9:0]};

    // PAGE: offset = address[10:0] (2KB); pma = cmem? get_pma : offset
    wire [10:0] off_p  = address[10:0];
    wire [10:0] pma_p  = cmem ? get_pma : off_p;
    // CHAR: offset = address[9:0]; cma = offset&7 (dblpage) o &0xf ; pma = cmem? get_pma : offset
    wire [9:0]  off_c  = address[9:0];
    wire [3:0]  cma    = dblpage ? {1'b0, off_c[2:0]} : off_c[3:0];
    wire [10:0] pma_c  = cmem ? get_pma : {1'b0, off_c};

    // lectura de página de la CPU (sirve para page-read y para pmd del char)
    wire [10:0] cpu_prd_addr = sel_char ? pma_c : pma_p;
    wire [7:0]  cpu_prd_q;
    wire [7:0]  pmd_cpu  = cpu_prd_q;                          // page[pma]
    // DRACO: dirección de CHAR/PCB = ((pmd<<3)|(cma&7)) — pmd directo, SIN column=0xff
    wire [10:0] char_idx = ((pmd_cpu << 3) | (cma & 3'd7)) & 11'h7ff;

    wire [7:0]  cpu_crd_q;     // char[char_idx]
    wire        cpu_pcbrd_q;   // pcb[char_idx] -> IN0[7]

    vis_vram u_vram (
        .clk(clk), .ce_pix(ce_pix),
        // lectura de vídeo
        .page_addr(v_page_addr), .page_q(v_page_q),
        .char_addr(v_char_addr), .char_q(v_char_q),
        .pcb_addr(v_pcb_addr),   .pcb_q(v_pcb_q),
        // lectura de CPU
        .cpu_prd_addr(cpu_prd_addr),   .cpu_prd_q(cpu_prd_q),
        .cpu_crd_addr(char_idx),       .cpu_crd_q(cpu_crd_q),
        .cpu_pcbrd_addr(char_idx),     .cpu_pcbrd_q(cpu_pcbrd_q),
        // escritura de CPU
        .cpu_page_we(ce_cpu && mem_write && sel_page), .cpu_page_addr(pma_p),   .cpu_page_d(cpu_dout),
        .cpu_char_we(ce_cpu && mem_write && sel_char), .cpu_char_addr(char_idx),.cpu_char_d(cpu_dout),
        .cpu_pcb_we (ce_cpu && mem_write && sel_char), .cpu_pcb_addr(char_idx), .cpu_pcb_d(q_out)
    );

    // ================= vídeo (modo Draco) =================
    vis_video u_video (
        .clk(clk), .reset(reset), .ce_pix(ce_pix),
        .bkg(bkg), .cfc(cfc), .col(col), .dispoff(dispoff),
        .freshorz(freshorz), .fresvert(fresvert), .line9(line9), .line16(line16),
        .dblpage(dblpage), .hma(hma_reg), .draco(1'b1),       // DRACO
        .page_addr(v_page_addr), .page_q(v_page_q),
        .char_addr(v_char_addr), .char_q(v_char_q),
        .pcb_addr(v_pcb_addr),   .pcb_q(v_pcb_q),
        .hcount(hcount), .vcount(vcount), .hsync(hsync), .vsync(vsync), .de(de),
        .prd_int(prd_int), .r(r), .g(g), .b(b)
    );

    // ================= sonido (COP402 + AY-3-8910) =================
    // OUT1 del 1802 (CDP1852 ic32): m_sound = (data & 0xe0) >> 5
    reg [2:0] sndcmd;
    wire out1 = io_active && mem_read && (cpu_io_port == 3'd1);
    always @(posedge clk) begin
        if (reset)            sndcmd <= 3'd0;
        else if (ce_cpu && out1) sndcmd <= io_data[7:5];
    end
    assign dbg_sndcmd = sndcmd;

    draco_sound u_sound (
        .clk(clk), .ce_cop(ce_cop), .ce_ay(ce_ay), .reset(reset),
        .sndcmd(sndcmd),
        .audio(audio),
        .dbg_cop_pc(), .dbg_cop_g(), .dbg_cop_q()
    );

    // ================= ROM / RAM =================
    (* ramstyle = "MLAB" *) reg [7:0] rom  [0:16383];
    (* ramstyle = "MLAB" *) reg [7:0] dram [0:1023] /*verilator public_flat_rd*/;

    // IN0 con bit7 = PCB (cdp1869_pcb_r). Latch del pcb leído en el último char-read.
    reg pcb_in0;
    always @(posedge clk) if (ce_cpu && mem_read && sel_char) pcb_in0 <= cpu_pcbrd_q;
    wire [7:0] in0_pcb = {pcb_in0, in0[6:0]};

    // INP1=IN0 ; INP2=IN1 ; INP4=IN2
    wire [7:0] io_in = (cpu_io_port == 3'd1) ? in0_pcb :
                       (cpu_io_port == 3'd2) ? in1 :
                       (cpu_io_port == 3'd4) ? in2 : 8'hff;

    wire [7:0] rom_q = rom[address[13:0]];   // ASÍNCRONO

    wire [7:0] mem_q = sel_rom  ? rom_q :
                       sel_ram  ? dram[address[9:0]] :
                       sel_char ? cpu_crd_q :
                       sel_page ? cpu_prd_q : 8'hff;

    assign io_data = mem_q;     // en OUT el dato = M(R(X))
    always @(*) begin
        if (io_active && mem_write) cpu_din = io_in;   // INP: bus del dispositivo
        else                        cpu_din = mem_q;
    end

    always @(posedge clk) begin
        if (ce_cpu && mem_write && sel_ram) dram[address[9:0]] <= cpu_dout;
        if (ioctl_rom_we)                   rom[ioctl_rom_addr] <= ioctl_rom_data;  // carga HPS
    end

`ifdef SIM
    initial $readmemh("../../roms/draco_prog.hex", rom);
`else
    initial $readmemh("draco_prog.hex", rom);
`endif
endmodule

`default_nettype wire
