// ============================================================================
//  vis_regs — Registros de control del CDP1869/1870 (OUT3..OUT7)
// ----------------------------------------------------------------------------
//  Bloque 1. Latch de los registros de vídeo/sonido del VIS.
//  Fuente de verdad: out3_w..out7_w de reference/mame/cdp1869.cpp y el wrapper
//  cidelsa_state::cdp1869_w (reference/mame/cidelsa_v.cpp).
//
//  TRUCO CLAVE DEL HW (verificado en MAME): la CPU escribe con OUT N (N=3..7).
//    - OUT3 usa el BYTE DE DATOS del bus  (data = M(R(X))).
//    - OUT4..7 usan la DIRECCIÓN del bus  (addr = R(X), get_memory_address()),
//      porque el payload es de hasta 16 bits y no cabe en el byte de datos.
//  Por eso este módulo recibe AMBOS: cpu_data (8b) y cpu_addr (16b).
//
//  Interfaz de escritura agnóstica del core de CPU: el glue del 1802 (bloque 5/6)
//  generará un pulso 'reg_wr' de 1 ciclo con reg_n = N (3..7) durante el ciclo OUT.
//  Reset: todos los campos a 0 (= device_start de MAME).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module vis_regs (
    input  wire        clk,
    input  wire        reset,

    // --- escritura de registro (1 pulso por OUT N válido, N en 3..7) ---
    input  wire        reg_wr,
    input  wire [2:0]  reg_n,       // 3..7
    input  wire [7:0]  cpu_data,    // payload de OUT3 (byte de datos)
    input  wire [15:0] cpu_addr,    // payload de OUT4..7 (dirección R(X))

    // --- out3: display y color ---
    output reg  [2:0]  bkg,         // color de fondo (R/G/B)
    output reg         cfc,         // color format control (0=color-on-color, 1=tone-on-tone)
    output reg         dispoff,     // display off
    output reg  [1:0]  col,         // modo de color
    output reg         freshorz,    // full-res horizontal (0 => ancho x2)

    // --- out4: tono (audio) ---
    output reg  [3:0]  toneamp,
    output reg  [2:0]  tonefreq,
    output reg         toneoff,
    output reg  [6:0]  tonediv,

    // --- out5: formato de vídeo + ruido ---
    output reg         cmem,        // char memory access mode
    output reg         line9,       // 9 líneas
    output reg         line16,      // 16 líneas hi-res
    output reg         dblpage,     // doble página
    output reg         fresvert,    // full-res vertical (0 => alto x2)
    output reg  [3:0]  wnamp,
    output reg  [2:0]  wnfreq,
    output reg         wnoff,

    // --- direcciones de página/home ---
    output reg  [10:0] pma,         // page memory address (out6, o out5 si cmem)
    output reg  [10:0] hma          // home address (out7), bits [1:0] = 0
);

    always @(posedge clk) begin
        if (reset) begin
            bkg      <= 3'd0;  cfc <= 1'b0;  dispoff <= 1'b0;  col <= 2'd0;  freshorz <= 1'b0;
            toneamp  <= 4'd0;  tonefreq <= 3'd0;  toneoff <= 1'b0;  tonediv <= 7'd0;
            cmem     <= 1'b0;  line9 <= 1'b0;  line16 <= 1'b0;  dblpage <= 1'b0;  fresvert <= 1'b0;
            wnamp    <= 4'd0;  wnfreq <= 3'd0;  wnoff <= 1'b0;
            pma      <= 11'd0; hma <= 11'd0;
        end else if (reg_wr) begin
            case (reg_n)
            3'd3: begin // out3_w(data) — payload = byte de datos
                bkg      <= cpu_data[2:0];
                cfc      <= cpu_data[3];
                dispoff  <= cpu_data[4];
                col      <= cpu_data[6:5];
                freshorz <= cpu_data[7];
            end
            3'd4: begin // out4_w(addr) — tono
                toneamp  <= cpu_addr[3:0];
                tonefreq <= cpu_addr[6:4];
                toneoff  <= cpu_addr[7];
                tonediv  <= cpu_addr[14:8];
            end
            3'd5: begin // out5_w(addr) — formato + ruido; además fija pma
                cmem     <= cpu_addr[0];
                line9    <= cpu_addr[3];
                line16   <= cpu_addr[5];
                dblpage  <= cpu_addr[6];
                fresvert <= cpu_addr[7];
                wnamp    <= cpu_addr[11:8];
                wnfreq   <= cpu_addr[14:12];
                wnoff    <= cpu_addr[15];
                // if (cmem) pma = offset; else pma = 0
                pma      <= cpu_addr[0] ? cpu_addr[10:0] : 11'd0;
            end
            3'd6: begin // out6_w(addr) — pma = addr & 0x7ff
                pma      <= cpu_addr[10:0];
            end
            3'd7: begin // out7_w(addr) — hma = addr & 0x7fc
                hma      <= {cpu_addr[10:2], 2'b00};
            end
            default: ; // N=0..2 no son del VIS
            endcase
        end
    end

endmodule

`default_nettype wire
