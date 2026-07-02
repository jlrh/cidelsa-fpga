//============================================================================
//  Cidelsa "Destroyer" (EFO/Cidelsa, 1980) para MiSTer — módulo `emu`.
//  Instancia rtl/cidelsa_machine.v (CPU CDP1802 + VIS CDP1869/1870, todo en BRAM,
//  SIN SDRAM) y lo cablea al framework MiSTer: vídeo por arcade_video, audio del
//  CDP1869 (tono+ruido), entradas por hps_io, carga de ROM (8KB) por ioctl.
//  Requiere el `sys/` de Template_MiSTer. Licencia GPLv2 (como el framework).
//
//  Relojes: PLL 50->30 MHz (clk_sys). El core es enable-gated: ce_cpu=3.579 MHz y
//  ce_pix=5.626 MHz (RELOJES REALES de Destroyer, manual de servicio) generados por
//  acumulador desde clk_sys. Fmax del core ~34 MHz -> 30 MHz cierra timing (+3.9 ns).
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

// ---- Puertos no usados (Cidelsa no usa SDRAM/DDR/UART/SD) ----
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_DTR, UART_TXD} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
// DDRAM lo conduce screen_rotate (framebuffer de rotación). FB_* los conduce screen_rotate
// salvo FB_FORCE_BLANK. Requiere MISTER_FB=1 en el .qsf.
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

//////////////////////////////////////////////////////////////////
// OSD: aspect ratio según orientación. Destroyer es de mueble VERTICAL.
//  status[2]=0 Vertical (rotado, 3:4) ; =1 Horizontal (raster nativo, 4:3).
wire [1:0] ar = status[122:121];
assign VIDEO_ARX = (!ar) ? (status[2] ? 12'd4 : 12'd3) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (status[2] ? 12'd3 : 12'd4) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"Destroyer;;",
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
	"J1,Fire,Start 1P,Start 2P,Coin;",
	"jn,A,Start,Select,R;",
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

///////////////////////   RELOJES   ///////////////////////////////
// clk = 30 MHz (clk_sys). El core genera su lógica con ce_cpu/ce_pix derivados.
wire clk, pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk),        // 30 MHz
	.locked(pll_locked)
);

// ce_pix=5.626 MHz (dot clock). ce_cpu = CICLO DE MÁQUINA del 1802 = reloj_1802/8.
//  El 1802 real hace 8 pulsos de reloj (3.579 MHz) por ciclo de máquina, y cdp1802_jl
//  avanza 1 ciclo de máquina por ce_cpu → ce_cpu = 3.579/8 = 447.375 kHz (NO 3.579 MHz,
//  que corría la CPU 8× de más). VALIDADO: con reloj/8 la ejecución == MAME (3000 OUTs).
localparam [15:0] CLK_KHZ = 16'd30000;
reg [16:0] acc_pix = 0, acc_cpu = 0;
reg        ce_pix = 0, ce_cpu = 0;
always @(posedge clk) begin
	if (acc_pix + 17'd5626 >= {1'b0,CLK_KHZ}) begin acc_pix <= acc_pix + 17'd5626 - {1'b0,CLK_KHZ}; ce_pix <= 1; end
	else begin acc_pix <= acc_pix + 17'd5626; ce_pix <= 0; end
	if (acc_cpu + 17'd447 >= {1'b0,CLK_KHZ}) begin acc_cpu <= acc_cpu + 17'd447 - {1'b0,CLK_KHZ}; ce_cpu <= 1; end
	else begin acc_cpu <= acc_cpu + 17'd447; ce_cpu <= 0; end
end

wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~pll_locked;

///////////////////////   ENTRADAS   //////////////////////////////
// IN0 (activo-BAJO): b0=cartucho, b1=Start1, b2=Start2, b3=Right, b4=Left, b5=Fire,
//                    b6=unused, b7=PCB (lo pone el core). El emu da in0[6:0].
// joystick_0: [0]=R [1]=L [2]=D [3]=U [4]=Fire [5]=Start1 [6]=Start2 [7]=Coin
wire [7:0] in0 = ~{ 1'b0,            // b7 (PCB, lo sobreescribe el core)
                    1'b0,            // b6 unused
                    joystick_0[4],   // b5 Fire
                    joystick_0[1],   // b4 Left
                    joystick_0[0],   // b3 Right
                    joystick_0[6],   // b2 Start2
                    joystick_0[5],   // b1 Start1
                    1'b0 };          // b0 cartucho (inactivo)

// IN1 = DIP switches. El juego los lee por INP2 (= in1) DIRECTAMENTE, así que in1 debe
// ser EXACTAMENTE el valor DIP que espera MAME (default 0xd6: Difficulty=0x02 Easy,
// Bonus=0x04 10000, Lives=0x10 3, Coinage=0xc0). Se cargan del .mra por HPS (ioctl 254)
// a sw[0]. El mapeo previo (~status) daba 0xff con el OSD por defecto → in1 equivocado
// → el juego desincronizaba el attract y salía el TEXTO SCRAMBLED. (VALIDADO: con in1=0xd6
// la ejecución == MAME, 3000 OUTs sin divergencia.)
reg [7:0] sw[8];
always @(posedge clk) if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;
wire [7:0] in1 = sw[0];

// EF (activo-ALTO): ef_ext[1]=Service(EF2), [2]=Coin2(EF3), [3]=Coin1(EF4). EF1=PRD (core).
wire [3:0] ef_ext = { joystick_0[7], joystick_1[7], 1'b0, 1'b0 };  // coin1=joy0[7], coin2=joy1[7]

///////////////////////   CARGA DE ROM (ioctl)   //////////////////
wire        rom_dl   = ioctl_download && (ioctl_index == 8'd0);
wire        rom_we   = rom_dl && ioctl_wr;
wire [12:0] rom_addr = ioctl_addr[12:0];

///////////////////////   CORE   //////////////////////////////////
wire [8:0] hcount, vcount;
wire       hsync, vsync, de;
wire [7:0] r, g, b;
wire signed [15:0] audio;

cidelsa_machine u_core
(
	.clk(clk), .ce_cpu(ce_cpu), .ce_pix(ce_pix), .reset(reset),
	.in0(in0), .in1(in1), .ef_ext(ef_ext),
	.ioctl_rom_we(rom_we), .ioctl_rom_addr(rom_addr), .ioctl_rom_data(ioctl_dout),
	.q_out(),
	.hcount(hcount), .vcount(vcount), .hsync(hsync), .vsync(vsync), .de(de),
	.r(r), .g(g), .b(b),
	.audio(audio),
	.io_active(), .io_is_out(), .io_port(), .io_data(), .io_addr(),
	.dbg_pc(), .dbg_fetch(), .dbg_rb(), .dbg_cfg(), .dbg_hma()
);

// Blanking derivado de hcount/vcount (ventana visible del CDP1870: H[30,324) V[10,304)).
wire hblank = ~((hcount >= 9'd30) && (hcount < 9'd324));
wire vblank = ~((vcount >= 9'd10) && (vcount < 9'd304));

///////////////////////   VÍDEO   /////////////////////////////////
// arcade_video escala; screen_rotate ROTA a vertical real (framebuffer en DDRAM,
// MISTER_FB=1 en el .qsf). Destroyer es de mueble VERTICAL.
//  status[2]=0 Vertical (no_rotate=0 → rota 90º, orientación correcta).
//  status[2]=1 Horizontal (no_rotate=1 → raster nativo, sin rotar).
//  status[6] Flip 180 (sentido de rotación en vertical / flip del framebuffer en horizontal).
wire no_rotate  = status[2] | direct_video;
wire rotate_ccw = status[6];
wire flip       = status[6];
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

///////////////////////   AUDIO   /////////////////////////////////
assign AUDIO_L = audio;
assign AUDIO_R = audio;
assign AUDIO_S = 1'b1;   // con signo

endmodule
