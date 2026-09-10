`default_nettype none

module cidelsa_mister_core (
    input  wire        clk_sys,
    input  wire        reset,

    input  wire [7:0]  joystick,
    input  wire [7:0]  dip,
    input  wire [3:0]  ef_ext,

    input  wire        rom_we,
    input  wire [12:0] rom_addr,
    input  wire [7:0]  rom_data,

    output wire        ce_vid,
    output wire [7:0]  VGA_R, VGA_G, VGA_B,
    output wire        VGA_HS, VGA_VS, VGA_DE,

    output wire signed [15:0] audio,

    output wire        q_out
);

    parameter [15:0] CLK_KHZ = 16'd30000;
    reg [16:0] acc_pix = 17'd0, acc_cpu = 17'd0;
    reg        ce_pix  = 1'b0,  ce_cpu  = 1'b0;
    always @(posedge clk_sys) begin
        if (acc_pix + 17'd5626 >= {1'b0,CLK_KHZ}) begin acc_pix <= acc_pix + 17'd5626 - {1'b0,CLK_KHZ}; ce_pix <= 1'b1; end
        else begin acc_pix <= acc_pix + 17'd5626; ce_pix <= 1'b0; end
        if (acc_cpu + 17'd3579 >= {1'b0,CLK_KHZ}) begin acc_cpu <= acc_cpu + 17'd3579 - {1'b0,CLK_KHZ}; ce_cpu <= 1'b1; end
        else begin acc_cpu <= acc_cpu + 17'd3579; ce_cpu <= 1'b0; end
    end
    assign ce_vid = ce_pix;

    wire [7:0] in0 = {1'b1, ~joystick[6:0]};
    wire [7:0] in1 = dip;

    wire [8:0] hcount, vcount;
    wire       hsync, vsync, de;
    wire [7:0] r, g, b;

    cidelsa_machine u_core (
        .clk(clk_sys), .ce_cpu(ce_cpu), .ce_pix(ce_pix), .reset(reset),
        .in0(in0), .in1(in1), .ef_ext(ef_ext),
        .q_out(q_out),
        .hcount(hcount), .vcount(vcount), .hsync(hsync), .vsync(vsync), .de(de),
        .r(r), .g(g), .b(b),
        .audio(audio),
        .io_active(), .io_is_out(), .io_port(), .io_data(), .io_addr(),
        .dbg_pc(), .dbg_fetch(), .dbg_rb(), .dbg_cfg(), .dbg_hma()
    );

    assign VGA_R = r; assign VGA_G = g; assign VGA_B = b;
    assign VGA_HS = hsync; assign VGA_VS = vsync; assign VGA_DE = de;

    wire _unused = &{1'b0, rom_we, rom_addr, rom_data};

endmodule

`default_nettype wire
