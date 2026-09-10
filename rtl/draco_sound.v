`default_nettype none

module draco_sound (
    input  wire        clk,
    input  wire        ce_cop,
    input  wire        ce_ay,
    input  wire        reset,

    input  wire [2:0]  sndcmd,

    input  wire        ioctl_rom_we,
    input  wire [10:0] ioctl_rom_addr,
    input  wire [7:0]  ioctl_rom_data,

    output wire signed [15:0] audio,

    output wire [9:0]  dbg_cop_pc,
    output wire [3:0]  dbg_cop_g,
    output wire [7:0]  dbg_cop_q
);

    wire [3:0] cop_g;
    wire [7:0] cop_q;
    wire [3:0] cop_d;
    reg  [7:0] psg_dout_latch;

    cop402_jl u_cop (
        .clk(clk), .ce(ce_cop), .reset(reset),
        .in_in({1'b0, ~sndcmd}),
        .l_in(psg_dout_latch),
        .g_out(cop_g), .q_out(cop_q), .d_out(cop_d), .l_out(),
        .sk_out(),
        .dbg_pc(dbg_cop_pc), .dbg_a(), .dbg_b(),
        .dbg_g(dbg_cop_g), .dbg_q(dbg_cop_q), .dbg_en(), .dbg_skip(),
        .ioctl_rom_we(ioctl_rom_we), .ioctl_rom_addr(ioctl_rom_addr), .ioctl_rom_data(ioctl_rom_data)
    );

    wire        bdir = cop_g[0];
    wire        bc1  = cop_g[1];
    wire [7:0]  ay_dout;
    wire [9:0]  ay_sound;
    wire [7:0]  ay_A, ay_B, ay_C;
    wire        ay_sample;

    always @(posedge clk) begin
        if (reset) psg_dout_latch <= 8'd0;
        else if (cop_g == 4'd2) psg_dout_latch <= ay_dout;
    end

    jt49_bus u_ay (
        .rst_n(~reset), .clk(clk), .clk_en(ce_ay),
        .bdir(bdir), .bc1(bc1), .din(cop_q),
        .sel(1'b1),
        .dout(ay_dout), .sound(ay_sound),
        .A(ay_A), .B(ay_B), .C(ay_C), .sample(ay_sample),
        .IOA_in(8'h00), .IOA_out(), .IOA_oe(),
        .IOB_in(8'h00), .IOB_out(), .IOB_oe()
    );

    assign audio = {1'b0, ay_sound, 5'd0} - 16'sd16384;
endmodule

`default_nettype wire
