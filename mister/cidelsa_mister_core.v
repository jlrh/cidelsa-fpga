// ============================================================================
//  cidelsa_mister_core — Lógica de integración del core Destroyer para MiSTer
// ----------------------------------------------------------------------------
//  Encapsula TODO lo específico del core (relojes/ce, instancia de
//  cidelsa_machine, mapeo de vídeo/audio/entradas) con una interfaz limpia y
//  agnóstica del framework, para conectar dentro del módulo `emu` del
//  Template_MiSTer (sys/) con muy poco cableado.
//
//  Relojes REALES de Destroyer (manual de servicio): CPU 3.579 MHz, dot 5.626 MHz.
//  Aquí se generan como clock-enables desde clk_sys (un PLL del template que dé,
//  p.ej., 50.0 MHz). Frecuencia media exacta por acumulador. ce_vid = ce_pix.
//
//  En `emu`:
//    - clk_sys  <= salida del PLL (outclk_0), ~50 MHz.
//    - reset    <= RESET | status[0] | buttons[1] | ioctl_download.
//    - joystick/ DIPs -> in0/in1 ; ROM por HPS (ioctl) -> rom_we/rom_addr/rom_data.
//    - vídeo -> CLK_VIDEO=clk_sys, CE_PIXEL=ce_vid, VGA_R/G/B, VGA_HS/VS/DE.
//    - audio -> AUDIO_L=AUDIO_R= {audio} ; AUDIO_S=1 (con signo).
//    - ROT90 (mueble vertical): lo hace el scaler (status rotate + VIDEO_ARX/ARY).
// ============================================================================
`default_nettype none

module cidelsa_mister_core (
    input  wire        clk_sys,       // ~50 MHz del PLL del template
    input  wire        reset,

    // --- entradas de juego (de hps_io) ---
    input  wire [7:0]  joystick,      // {.., fire, up,down,left,right} (mapea a in0)
    input  wire [7:0]  dip,           // DIPs (mapea a in1)
    input  wire [3:0]  ef_ext,        // service/coin externos (EF2..4)

    // --- carga de ROM por HPS (ioctl_download) ---
    input  wire        rom_we,
    input  wire [12:0] rom_addr,      // 0..8191
    input  wire [7:0]  rom_data,

    // --- vídeo ---
    output wire        ce_vid,        // CE_PIXEL (= ce_pix)
    output wire [7:0]  VGA_R, VGA_G, VGA_B,
    output wire        VGA_HS, VGA_VS, VGA_DE,

    // --- audio ---
    output wire signed [15:0] audio,

    // --- otros ---
    output wire        q_out
);
    // ---- generación de clock-enables (frecuencia media exacta desde clk_sys) ----
    //  CLK_KHZ = frecuencia de clk_sys en kHz. Fmax del core ≈ 34 MHz → usar un PLL
    //  que dé clk_sys <= ~33 MHz (p.ej. 30 MHz, timing cerrado con +3.9 ns de slack).
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

    // ---- mapeo de entradas ----
    //  in0: controles del jugador (bit7 = PCB, lo pone el core; activo-bajo en HW).
    //  Ajustar el mapeo bit a bit del joystick al pinout real de Destroyer.
    wire [7:0] in0 = {1'b1, ~joystick[6:0]};
    wire [7:0] in1 = dip;

    // ---- core ----
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

    // NOTA: la ROM va dentro de cidelsa_machine con $readmemh. Para carga por HPS
    // (ioctl) hay que exponer un puerto de escritura a la `rom` de cidelsa_machine
    // (rom_we/rom_addr/rom_data). Pendiente al integrar con el .mra. De momento la
    // ROM se inicializa por $readmemh (síntesis) — válido para arrancar en HW.
    wire _unused = &{1'b0, rom_we, rom_addr, rom_data};

endmodule

`default_nettype wire
