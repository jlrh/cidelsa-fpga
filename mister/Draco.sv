module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_DTR, UART_TXD} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign FB_FORCE_BLANK = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = ioctl_download;
assign BUTTONS = 0;
assign AUDIO_MIX = 0;

wire [1:0] ar = status[122:121];
assign VIDEO_ARX = (!ar) ? (status[2] ? 12'd4 : 12'd3) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (status[2] ? 12'd3 : 12'd4) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"Draco;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[2],Orientation,Vertical,Horizontal;",
	"O[6],Flip 180,Off,On;",
	"O[3],Scandoubler FX,Off,On;",
	"-;",
	"DIP;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"-;",
	"J1,Start 1P,Start 2P,Coin;",
	"J2;",
	"jn,Start,Select,R;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire        direct_video;
wire [127:0] status;
wire  [1:0] buttons;
wire [31:0] joystick_0, joystick_1;
wire [21:0] gamma_bus;

wire        ioctl_download;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_wr;
wire  [7:0] ioctl_index;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk),
	.HPS_BUS(HPS_BUS),
	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),
	.buttons(buttons),
	.status(status),
	.gamma_bus(gamma_bus),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ioctl_download(ioctl_download),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr(ioctl_wr),
	.ioctl_index(ioctl_index)
);

wire clk, pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk),
	.locked(pll_locked)
);

localparam [15:0] CLK_KHZ = 16'd28130;
reg [16:0] acc_pix = 0, acc_cpu = 0;
reg [16:0] acc_cop = 0, acc_ay  = 0;
reg        ce_pix  = 0, ce_cpu  = 0;
reg        ce_cop  = 0, ce_ay   = 0;
always @(posedge clk) begin
	if (acc_pix + 17'd5626 >= {1'b0,CLK_KHZ}) begin acc_pix <= acc_pix + 17'd5626 - {1'b0,CLK_KHZ}; ce_pix <= 1; end
	else begin acc_pix <= acc_pix + 17'd5626; ce_pix <= 0; end

	if (acc_cpu + 17'd554 >= {1'b0,CLK_KHZ}) begin acc_cpu <= acc_cpu + 17'd554 - {1'b0,CLK_KHZ}; ce_cpu <= 1; end
	else begin acc_cpu <= acc_cpu + 17'd554; ce_cpu <= 0; end

	if (acc_cop + 17'd126 >= {1'b0,CLK_KHZ}) begin acc_cop <= acc_cop + 17'd126 - {1'b0,CLK_KHZ}; ce_cop <= 1; end
	else begin acc_cop <= acc_cop + 17'd126; ce_cop <= 0; end

	if (acc_ay + 17'd2012 >= {1'b0,CLK_KHZ}) begin acc_ay <= acc_ay + 17'd2012 - {1'b0,CLK_KHZ}; ce_ay <= 1; end
	else begin acc_ay <= acc_ay + 17'd2012; ce_ay <= 0; end
end

wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~pll_locked;

wire [7:0] in0 = ~{ 1'b0,
                    3'b0,
                    1'b0,
                    1'b0,
                    joystick_0[5],
                    joystick_0[4] };

wire [7:0] in2 = ~{ joystick_1[1], joystick_1[0], joystick_1[2], joystick_1[3],
                     joystick_0[1], joystick_0[0], joystick_0[2], joystick_0[3] };

reg [7:0] sw[8];
always @(posedge clk) if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;
wire [7:0] in1 = sw[0];

wire coin1_clean, coin2_clean;
coin_debounce u_coin1 (.clk(clk), .raw(joystick_0[6]), .clean(coin1_clean));
coin_debounce u_coin2 (.clk(clk), .raw(joystick_1[6]), .clean(coin2_clean));
wire [3:0] ef_ext = { coin1_clean, coin2_clean, 1'b0, 1'b0 };

wire        rom_dl   = ioctl_download && (ioctl_index == 8'd0);
wire        rom_we   = rom_dl && ioctl_wr;
wire [13:0] rom_addr = ioctl_addr[13:0];

wire        snd_dl   = ioctl_download && (ioctl_index == 8'd1);
wire        snd_we   = snd_dl && ioctl_wr;
wire [10:0] snd_addr = ioctl_addr[10:0];

wire [8:0] hcount, vcount;
wire       hsync, vsync, de;
wire [7:0] r, g, b;
wire signed [15:0] audio;

draco_machine u_core
(
	.clk(clk), .ce_cpu(ce_cpu), .ce_pix(ce_pix), .ce_cop(ce_cop), .ce_ay(ce_ay), .reset(reset), .flip(native_flip),
	.in0(in0), .in1(in1), .in2(in2), .ef_ext(ef_ext),
	.ioctl_rom_we(rom_we), .ioctl_rom_addr(rom_addr), .ioctl_rom_data(ioctl_dout),
	.ioctl_snd_we(snd_we), .ioctl_snd_addr(snd_addr), .ioctl_snd_data(ioctl_dout),
	.q_out(),
	.hcount(hcount), .vcount(vcount), .hsync(hsync), .vsync(vsync), .de(de),
	.r(r), .g(g), .b(b),
	.audio(audio),
	.io_active(), .io_is_out(), .io_port(), .io_data(), .io_addr(),
	.dbg_pc(), .dbg_fetch(), .dbg_rb(), .dbg_sndcmd()
);

wire hblank = ~((hcount >= 9'd30) && (hcount < 9'd324));
wire vblank = ~((vcount >= 9'd10) && (vcount < 9'd304));

wire no_rotate  = status[2] | direct_video;

wire rotate_ccw = 1'b0;
wire flip       = 1'b0;

wire native_flip = status[6];
wire video_rotated;
screen_rotate screen_rotate (.*);

arcade_video #(.WIDTH(320), .DW(24)) arcade_video
(
	.*,
	.clk_video(clk),
	.ce_pix(ce_pix),
	.RGB_in({r, g, b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hsync),
	.VSync(vsync),
	.fx(status[3] ? 3'd1 : 3'd0)
);

assign AUDIO_L = audio;
assign AUDIO_R = audio;
assign AUDIO_S = 1'b1;

endmodule
