`timescale 1ns/1ps
`default_nettype none

module draco_machine (
    input  wire        clk,
    input  wire        ce_cpu,
    input  wire        ce_pix,
    input  wire        ce_cop,
    input  wire        ce_ay,
    input  wire        reset,
    input  wire        flip,

    input  wire [7:0]  in0,
    input  wire [7:0]  in1,
    input  wire [7:0]  in2,
    input  wire [3:0]  ef_ext,

    input  wire        ioctl_rom_we,
    input  wire [13:0] ioctl_rom_addr,
    input  wire [7:0]  ioctl_rom_data,

    input  wire        ioctl_snd_we,
    input  wire [10:0] ioctl_snd_addr,
    input  wire [7:0]  ioctl_snd_data,

    output wire        q_out,

    output wire [8:0]  hcount, vcount,
    output wire        hsync, vsync, de,
    output wire [7:0]  r, g, b,

    output wire signed [15:0] audio,

    output wire        io_active, io_is_out,
    output wire [2:0]  io_port,
    output wire [7:0]  io_data,
    output wire [15:0] io_addr,
    output wire [15:0] dbg_pc,
    output wire        dbg_fetch,
    output wire [15:0] dbg_rb,
    output wire [2:0]  dbg_sndcmd
);

    wire [15:0] address;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din;
    wire        mem_read, mem_write;
    wire [2:0]  cpu_io_port;
    wire [1:0]  sc;
    wire [15:0] cpu_pc;

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

    wire [10:0] v_page_addr, v_char_addr, v_pcb_addr;
    wire [7:0]  v_page_q, v_char_q; wire v_pcb_q;

    wire sel_rom  = (address < 16'h4000);
    wire sel_ram  = (address >= 16'h8000) && (address <= 16'h83ff);
    wire sel_char = (address >= 16'hf400) && (address <= 16'hf7ff);
    wire sel_page = (address >= 16'hf800);

    wire [10:0] get_pma = dblpage ? pma_reg : {1'b0, pma_reg[9:0]};

    wire [10:0] off_p  = address[10:0];
    wire [10:0] pma_p  = cmem ? get_pma : off_p;

    wire [9:0]  off_c  = address[9:0];
    wire [3:0]  cma    = dblpage ? {1'b0, off_c[2:0]} : off_c[3:0];
    wire [10:0] pma_c  = cmem ? get_pma : {1'b0, off_c};

    wire [10:0] cpu_prd_addr = sel_char ? pma_c : pma_p;
    wire [7:0]  cpu_prd_q;
    wire [7:0]  pmd_cpu  = cpu_prd_q;

    wire [10:0] char_idx = ((pmd_cpu << 3) | (cma & 3'd7)) & 11'h7ff;

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

    vis_video u_video (
        .clk(clk), .reset(reset), .ce_pix(ce_pix),
        .bkg(bkg), .cfc(cfc), .col(col), .dispoff(dispoff),
        .freshorz(freshorz), .fresvert(fresvert), .line9(line9), .line16(line16),
        .dblpage(dblpage), .hma(hma_reg), .draco(1'b1),
        .flip(flip),
        .page_addr(v_page_addr), .page_q(v_page_q),
        .char_addr(v_char_addr), .char_q(v_char_q),
        .pcb_addr(v_pcb_addr),   .pcb_q(v_pcb_q),
        .hcount(hcount), .vcount(vcount), .hsync(hsync), .vsync(vsync), .de(de),
        .prd_int(prd_int), .r(r), .g(g), .b(b)
    );

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
        .ioctl_rom_we(ioctl_snd_we), .ioctl_rom_addr(ioctl_snd_addr), .ioctl_rom_data(ioctl_snd_data),
        .audio(audio),
        .dbg_cop_pc(), .dbg_cop_g(), .dbg_cop_q()
    );

    (* ramstyle = "MLAB, no_rw_check" *) reg [7:0] rom  [0:16383];
    (* ramstyle = "MLAB, no_rw_check" *) reg [7:0] dram [0:1023] /*verilator public_flat_rd*/;

    reg pcb_in0;
    always @(posedge clk) if (ce_cpu && mem_read && sel_char) pcb_in0 <= cpu_pcbrd_q;
    wire [7:0] in0_pcb = {pcb_in0, in0[6:0]};

    wire [7:0] io_in = (cpu_io_port == 3'd1) ? in0_pcb :
                       (cpu_io_port == 3'd2) ? in1 :
                       (cpu_io_port == 3'd4) ? in2 : 8'hff;

    wire [7:0] rom_q = rom[address[13:0]];

    wire [7:0] mem_q = sel_rom  ? rom_q :
                       sel_ram  ? dram[address[9:0]] :
                       sel_char ? cpu_crd_q :
                       sel_page ? cpu_prd_q : 8'hff;

    assign io_data = mem_q;
    always @(*) begin
        if (io_active && mem_write) cpu_din = io_in;
        else                        cpu_din = mem_q;
    end

    always @(posedge clk) begin
        if (ce_cpu && mem_write && sel_ram) dram[address[9:0]] <= cpu_dout;
        if (ioctl_rom_we)                   rom[ioctl_rom_addr] <= ioctl_rom_data;
    end

`ifdef SIM
    initial $readmemh("../../roms/draco_prog.hex", rom);
`else
    initial $readmemh("draco_prog.hex", rom);
`endif
endmodule

`default_nettype wire
