// ============================================================================
//  cidelsa_machine — Sistema Destroyer COMPLETO (CPU 1802 + VIS + memoria + I/O)
// ----------------------------------------------------------------------------
//  Integra: CPU cdp1802_jl + ROM 8K + NVRAM 256B + vis_vram (PAGE/CHAR/PCB
//  compartida) + vis_regs (OUT3-7) + vis_video (timing+fetch+color, pixel-perfect).
//  Direccionamiento 1869 real de CHAR/PAGE (cidelsa_v.cpp) para los accesos CPU.
//  EF1/INT del 1802 = ~PRD (prd_int del timing de vídeo).
//
//  Mapa (destryer): 0x0000-1FFF ROM | 0x2000-20FF NVRAM | 0xF400-F7FF CHAR |
//                   0xF800-FFFF PAGE.  INP1=IN0 INP2=IN1  OUT3-7=registros 1869.
//  Dos relojes (un clk + ce): ce_cpu (3.579 MHz) y ce_pix (dot 5.7143/5.626 MHz).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

// NOTA DE MEMORIA: el CDP1802 lee y usa memoria en el MISMO ciclo (combinacional).
// VALIDADO que una lectura registrada (1 clk de latencia) ROMPE el CPU (diverge en la
// 1ª OUT, incluso con clk>>ce). Por eso TODAS las memorias del bus de CPU son de
// lectura ASÍNCRONA. En la Cyclone V se mapean a LUTRAM/MLAB (que soporta async-read)
// vía el atributo ramstyle="MLAB" en cada array.

module cidelsa_machine (
    input  wire        clk,
    input  wire        ce_cpu,
    input  wire        ce_pix,
    input  wire        reset,

    input  wire [7:0]  in0,         // IN0 (controles; bit7 = PCB, lo pone el HW)
    input  wire [7:0]  in1,         // IN1 (DIPs)
    input  wire [3:0]  ef_ext,      // EF2..EF4 externos (service/coin) en bits[3:1]; EF1 lo pone PRD

    // --- carga de ROM por HPS (MiSTer ioctl); opcional: si no se usa, la ROM la
    //     inicializa $readmemh (válido en SIM y horneada en el bitstream de síntesis) ---
    input  wire        ioctl_rom_we,
    input  wire [12:0] ioctl_rom_addr,
    input  wire [7:0]  ioctl_rom_data,

    output wire        q_out,

    // --- vídeo ---
    output wire [8:0]  hcount, vcount,
    output wire        hsync, vsync, de,
    output wire [7:0]  r, g, b,

    // --- audio ---
    output wire signed [15:0] audio,

    // --- traza de I/O (debug/validación) ---
    output wire        io_active, io_is_out,
    output wire [2:0]  io_port,
    output wire [7:0]  io_data,
    output wire [15:0] io_addr,
    output wire [15:0] dbg_pc,
    output wire        dbg_fetch,
    output wire [15:0] dbg_rb,
    output wire [15:0] dbg_cfg,     // {dispoff,dblpage,line16,line9,fresvert,freshorz,cfc,col,bkg}
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

    // EF1 = ~PRD (prd_int=1 en vblank); EF2..4 externos
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

    // --- direccionamiento 1869 de los accesos CPU a CHAR/PAGE (cidelsa_v.cpp) ---
    wire sel_rom   = (address < 16'h2000);
    wire sel_nvram = (address >= 16'h2000) && (address <= 16'h20ff);
    wire sel_char  = (address >= 16'hf400) && (address <= 16'hf7ff);
    wire sel_page  = (address >= 16'hf800);

    // get_pma(): dblpage ? pma_reg : pma_reg & 0x3ff
    wire [10:0] get_pma = dblpage ? pma_reg : {1'b0, pma_reg[9:0]};

    // PAGE: offset = address[10:0]; pma = cmem? get_pma : offset
    wire [10:0] off_p  = address[10:0];
    wire [10:0] pma_p  = cmem ? get_pma : off_p;
    // CHAR: offset = address[9:0]; cma = offset[3:0]; pma = cmem? get_pma : offset
    wire [9:0]  off_c  = address[9:0];
    wire [3:0]  cma    = dblpage ? {1'b0, off_c[2:0]} : off_c[3:0];   // cma&7 si dblpage
    wire [10:0] pma_c  = cmem ? get_pma : {1'b0, off_c};

    // lectura de página de la CPU (sirve para page-read y para pmd del char)
    wire [10:0] cpu_prd_addr = sel_char ? pma_c : pma_p;
    wire [7:0]  cpu_prd_q;
    wire [7:0]  pmd_cpu   = cpu_prd_q;                       // page[pma]
    wire [7:0]  column    = pma_c[10] ? 8'hff : pmd_cpu;
    wire [10:0] char_idx  = ((column << 3) | (cma & 3'd7)) & 11'h7ff;   // dir. CHAR (write/read, column)
    // NOTA: IN0[7] (bit PCB) = m_cdp1869_pcb, que en MAME lo pone `cidelsa_charram_r`
    // (cidelsa_v.cpp:40-46) con el addr POR COLUMN (= char_idx), NO el pmd-directo de
    // `cidelsa_pcb_r` (que es solo para el color de display, ruta v_pcb_addr en vis_video).
    // Antes se usaba pcb_idx (pmd) → IN0[7] divergía cuando pma[10]=1 → el CPU tomaba otra
    // rama en la rutina de redef de chars del attract → char writes cmem=0 → glyph 0xff roto.

    wire [7:0]  cpu_crd_q;     // char[char_idx]
    wire        cpu_pcbrd_q;   // pcb[char_idx] -> IN0[7] (como cidelsa_charram_r de MAME)

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

    // ================= vídeo =================
    vis_video u_video (
        .clk(clk), .reset(reset), .ce_pix(ce_pix),
        .bkg(bkg), .cfc(cfc), .col(col), .dispoff(dispoff),
        .freshorz(freshorz), .fresvert(fresvert), .line9(line9), .line16(line16),
        .dblpage(dblpage), .hma(hma_reg), .draco(1'b0),   // Destroyer = Cidelsa, no Draco
        .page_addr(v_page_addr), .page_q(v_page_q),
        .char_addr(v_char_addr), .char_q(v_char_q),
        .pcb_addr(v_pcb_addr),   .pcb_q(v_pcb_q),
        .hcount(hcount), .vcount(vcount), .hsync(hsync), .vsync(vsync), .de(de),
        .prd_int(prd_int), .r(r), .g(g), .b(b)
    );

    // ================= sonido =================
    vis_sound u_sound (
        .clk(clk), .reset(reset), .ce_pix(ce_pix),
        .toneamp(toneamp), .tonefreq(tonefreq), .toneoff(toneoff), .tonediv(tonediv),
        .wnamp(wnamp), .wnfreq(wnfreq), .wnoff(wnoff),
        .audio(audio)
    );

    // ================= ROM / NVRAM =================
    // ramstyle="MLAB" → LUTRAM de lectura asíncrona (el CPU necesita async). Sin esto
    // Quartus intenta M10K (lectura registrada) con una ROM async de 64Kbit y se atasca.
    (* ramstyle = "M10K" *) reg [7:0] rom   [0:8191];
    (* ramstyle = "M10K" *) reg [7:0] nvram [0:255] /*verilator public_flat_rd*/;

    // IN0 con bit7 = PCB (cdp1869_pcb_r). Latch del pcb leído en el último char-read.
    reg pcb_in0;
    always @(posedge clk) if (ce_cpu && mem_read && sel_char) pcb_in0 <= cpu_pcbrd_q;
    wire [7:0] in0_pcb = {pcb_in0, in0[6:0]};

    wire [7:0] io_in = (cpu_io_port == 3'd1) ? in0_pcb :
                       (cpu_io_port == 3'd2) ? in1 : 8'hff;

    // Lectura de ROM/NVRAM REGISTRADA en clk LIBRE (→ M10K). Como `address` es estable
    // todo el paso de ce y clk≫ce_cpu, el dato llega válido al borde de ce_cpu (igual que
    // las copias de CPU de vis_vram). cpu_crd_q/cpu_prd_q ya vienen registradas de vis_vram.
    reg [7:0] rom_q, nvram_q;
`ifdef MEM_ASYNC
    always @(*) begin
        rom_q   = rom[address[12:0]];
        nvram_q = nvram[address[7:0]];
    end
`else
    always @(posedge clk) begin
        rom_q   <= rom[address[12:0]];
        nvram_q <= nvram[address[7:0]];
    end
`endif

    wire [7:0] mem_q = sel_rom   ? rom_q :
                       sel_nvram ? nvram_q :
                       sel_char  ? cpu_crd_q :
                       sel_page  ? cpu_prd_q : 8'hff;

    assign io_data = mem_q;     // en OUT el dato = M(R(X))
    always @(*) begin
        if (io_active && mem_write) cpu_din = io_in;   // INP: bus del dispositivo
        else                        cpu_din = mem_q;
    end

    always @(posedge clk) begin
        if (ce_cpu && mem_write && sel_nvram) nvram[address[7:0]] <= cpu_dout;
        if (ioctl_rom_we)                     rom[ioctl_rom_addr]  <= ioctl_rom_data;  // carga HPS
    end

`ifdef SIM
    initial $readmemh("../../roms/destryer_prog.hex", rom);
`else
    // síntesis (Quartus): el .hex se busca relativo al directorio del proyecto
    initial $readmemh("destryer_prog.hex", rom);
`endif

`ifdef CHARTRACE
    // Traza de escrituras CHAR que caen en los glifos 0xbe (idx 0x5f0..0x5f7)
    // y 0xff (idx 0x7f8..0x7ff), con todo el contexto del direccionamiento 1869.
    always @(posedge clk) if (ce_cpu && mem_write && sel_char) begin
        if ((char_idx >= 11'h5f0 && char_idx <= 11'h5f7) ||
            (char_idx >= 11'h7f8 && char_idx <= 11'h7ff))
            $display("CW addr=%04x cmem=%b dbl=%b pma=%03x pma10=%b pmd=%02x col=%02x cma=%0d idx=%03x data=%02x q=%b",
                address, cmem, dblpage, pma_c, pma_c[10], pmd_cpu, column, cma, char_idx, cpu_dout, q_out);
    end
`endif

`ifdef WRITETRACE
    // Traza de TODAS las escrituras (char/page/nvram) con PC (para diff sim vs MAME).
    always @(posedge clk) if (ce_cpu && mem_write)
        $display("W pc=%04x addr=%04x data=%02x cmem=%b dbl=%b %s",
            cpu_pc, address, cpu_dout, cmem, dblpage,
            sel_char ? "CHAR" : sel_page ? "PAGE" : sel_nvram ? "NVRAM" : "OTHER");
`endif
endmodule

`default_nettype wire
