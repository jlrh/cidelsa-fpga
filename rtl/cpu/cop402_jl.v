// ============================================================================
//  cop402_jl — CPU de sonido National COP402 (familia COP400, 4 bits) en Verilog.
// ----------------------------------------------------------------------------
//  Traducción de MAME (reference/mame/cop400.cpp + cop400op.hxx, mapa COP420).
//  Para el sonido de DRACO (Cidelsa). UN INSTRUCCIÓN por pulso de `ce`. ROM 2KB
//  banqueada (bank=D3) en 0x000-0x3ff; RAM 64×4. Modelo MAME: al ejecutar, PC ya
//  está incrementado (pc_after = PC + longitud); los saltos lo sobreescriben.
//
//  Validable contra debug/destryer/dumps/cop_trace_mame.txt (PC,A,B,G,Q,EN por
//  instrucción EJECUTADA). dbg_skip=1 → esta instrucción se salta (no logar).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module cop402_jl (
    input  wire        clk,
    input  wire        ce,
    input  wire        reset,

    input  wire [3:0]  in_in,         // puerto IN (cmd sonido del 1802)
    input  wire [7:0]  l_in,          // puerto L (entrada AY)
    output reg  [3:0]  g_out,         // puerto G (control AY)
    output reg  [7:0]  q_out,         // latch Q (→ L = datos AY)
    output reg  [3:0]  d_out,         // puerto D (D3 = bank ROM)
    output reg  [7:0]  l_out,         // L de salida (cuando EN[2])
    output wire        sk_out,

    output wire [9:0]  dbg_pc,
    output wire [3:0]  dbg_a,
    output wire [5:0]  dbg_b,
    output wire [3:0]  dbg_g,
    output wire [7:0]  dbg_q,
    output wire [3:0]  dbg_en,
    output wire        dbg_skip
);
    // ---- ROM 2KB banqueada ----
    reg [7:0] rom [0:2047];
`ifdef SIM
    initial $readmemh("../../roms/draco_sound.hex", rom);
`endif
    function [7:0] romrd(input [9:0] a); romrd = rom[{d_out[3], a}]; endfunction

    // ---- RAM 64×4 ----
    reg [3:0] ram [0:63];

    // ---- registros ----
    reg [9:0] PC;
    reg [3:0] A;
    reg [5:0] B;          // Br[5:4], Bd[3:0]
    reg       C;
    reg [3:0] EN;
    reg [7:0] Q;
    reg [9:0] SA, SB, SC;
    reg [3:0] SIO;
    reg [7:0] T;
    reg       SKL;
    reg       skt_latch;
    reg [2:0] tcyc;       // acumulador de ciclos para el timer (T++ cada 4)
    reg       skip;
    reg [1:0] skip_lbi;
    reg       last_skip;

    assign dbg_pc=PC; assign dbg_a=A; assign dbg_b=B; assign dbg_g=g_out;
    assign dbg_q=Q; assign dbg_en=EN; assign dbg_skip=skip;
    assign sk_out = (~EN[0]) ? SKL : C;   // SK = SKL (si EN0=0) / C aprox

    // 2-byte: 0x33, 0x23, 0x60-0x63 (JMP), 0x68-0x6B (JSR)
    function is2(input [7:0] op);
        is2 = (op==8'h33) || (op==8'h23) ||
              (op>=8'h60 && op<=8'h63) || (op>=8'h68 && op<=8'h6B);
    endfunction

    // tareas auxiliares (combinacionales sobre regs)
    reg [7:0] op, operand, op2;
    reg [9:0] pc_after, jaddr;
    reg [4:0] add5;
    reg [3:0] rb;            // RAM(B)
    reg [3:0] ynib;
    reg       do_skip;       // marcar skip de la SIGUIENTE

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            PC<=0; A<=0; B<=0; C<=0; EN<=0; Q<=0; SA<=0; SB<=0; SC<=0; SIO<=0; T<=0;
            SKL<=1; skt_latch<=0; tcyc=0; skip<=0; skip_lbi<=0; last_skip<=0;
            g_out<=0; q_out<=0; d_out<=0; l_out<=0;
        end else if (ce) begin
            op       = romrd(PC);
            operand  = romrd(PC + 10'd1);
            pc_after = PC + (is2(op) ? 10'd2 : 10'd1);
            rb       = ram[B];
            do_skip  = 1'b0;

            // ---- TIMER: T++ cada 4 ciclos (cki*4 clocks); instlen ciclos/instrucción.
            //  Avanza SIEMPRE (ejecute o salte). Al desbordar (0xFF→0x00) setea skt_latch.
            tcyc = tcyc + (is2(op) ? 3'd2 : 3'd1);
            if (tcyc >= 3'd4) begin
                tcyc = tcyc - 3'd4;
                T <= T + 8'd1;
                if (T == 8'hFF) skt_latch <= 1'b1;   // SKT lo limpia al leerlo
            end

            if (skip) begin
                // saltar esta instrucción (no ejecutar, no logar)
                skip <= 1'b0;
                PC   <= pc_after;
            end else begin
                PC <= pc_after;                  // por defecto; saltos sobreescriben
                if (skip_lbi != 0) skip_lbi <= skip_lbi - 2'd1;

                casez (op)
                // ===== opcodes ESPECÍFICOS (antes que los comodines de columna) =====
                8'h00: A <= 4'd0;                                       // CLRA
                8'h02: A <= A ^ rb;                                     // XOR
                8'h10: begin add5=(A^4'hF)+rb+C; A<=add5[3:0]; if(add5[4]) begin C<=1; do_skip=1; end else C<=0; end // CASC
                8'h12: begin A <= {2'd0,B[5:4]}; B <= {A[1:0],B[3:0]}; end // XABR
                8'h20: if(C) do_skip=1;                                 // SKC
                8'h21: if(A==rb) do_skip=1;                             // SKE
                8'h22: C <= 1'b1;                                       // SC
                8'h30: begin add5=A+C+rb; A<=add5[3:0]; if(add5[4]) begin C<=1; do_skip=1; end else C<=0; end // ASC
                8'h31: A <= A + rb;                                     // ADD
                8'h32: C <= 1'b0;                                       // RC
                8'h40: A <= A ^ 4'hF;                                   // COMP
                8'h41: if(skt_latch) begin skt_latch<=0; do_skip=1; end // SKT
                8'h42: ram[B] <= rb & 4'hB;                             // RMB2
                8'h43: ram[B] <= rb & 4'h7;                             // RMB3
                8'h44: ;                                                // NOP
                8'h45: ram[B] <= rb & 4'hD;                             // RMB1
                8'h46: ram[B] <= rb | 4'h4;                             // SMB2
                8'h47: ram[B] <= rb | 4'h2;                             // SMB1
                8'h48: begin PC<=SA; SA<=SB; SB<=SC; skip<=last_skip; end // RET
                8'h49: begin PC<=SA; SA<=SB; SB<=SC; do_skip=1; end      // RETSK
                8'h4A: A <= A + 4'd10;                                  // ADT
                8'h4B: ram[B] <= rb | 4'h8;                             // SMB3
                8'h4C: ram[B] <= rb & 4'hE;                             // RMB0
                8'h4D: ram[B] <= rb | 4'h1;                             // SMB0
                8'h4E: A <= B[3:0];                                     // CBA
                8'h4F: begin SIO<=A; A<=SIO; SKL<=C; end                // XAS
                8'h50: B <= {B[5:4], A};                                // CAB
                // skmbz0..3 (0x01,0x11,0x03,0x13): skip si bit de RAM(B) = 0
                8'h01: if(!rb[0]) do_skip=1;
                8'h11: if(!rb[1]) do_skip=1;
                8'h03: if(!rb[2]) do_skip=1;
                8'h13: if(!rb[3]) do_skip=1;
                // ===== comodines de columna =====
                8'b0101_????: begin add5=A+op[3:0]; A<=add5[3:0]; if(add5[4]) do_skip=1; end // AISC (0x51-0x5F)
                8'b00??_1???: begin B <= {op[5:4], (op[3:0]+4'd1)}; end // LBI single-byte
                8'b00??_0101: begin A<=rb; B<=B ^ {op[5:4],4'd0}; end   // LD
                8'b00??_0110: begin ram[B]<=A; A<=rb; B<=B ^ {op[5:4],4'd0}; end // X
                8'b00??_0100: begin ram[B]<=A; A<=rb; B<={B[5:4]^op[5:4],(B[3:0]+4'd1)}; if(B[3:0]==4'hF) do_skip=1; end // XIS
                8'b00??_0111: begin ram[B]<=A; A<=rb; B<={B[5:4]^op[5:4],(B[3:0]-4'd1)}; if(B[3:0]==4'h0) do_skip=1; end // XDS
                8'b0111_????: begin ram[B]<=op[3:0]; B<={B[5:4],(B[3:0]+4'd1)}; end // STII
                8'b0110_0_0??: PC <= (({op[2:0],operand}) & 10'h3ff);     // JMP (0x60-0x63)
                8'b0110_1_0??: begin SC<=SB; SB<=SA; SA<=pc_after; PC <= (({op[2:0],operand}) & 10'h3ff); end // JSR (0x68-0x6B)
                // JP (0x80-0xFF salvo 0xBF=LQID, 0xFF=JID)
                8'b1???_????: begin
                    if(op==8'hBF) begin   // LQID
                        SC<=SB; SB<=SA; SA<=pc_after;            // PUSH
                        jaddr = {pc_after[9:8], A, ram[B]};      // (PC&0x700)|(A<<4)|RAM(B)
                        Q <= romrd(jaddr); if(EN[2]) l_out<=romrd(jaddr); q_out<=romrd(jaddr);
                        PC <= pc_after;                          // POP (neto)
                    end else if(op==8'hFF) begin // JID
                        jaddr = {pc_after[9:8], A, ram[B]};
                        op2 = romrd(jaddr);
                        PC <= {jaddr[9:8], op2};
                    end else if(pc_after[9:6]==4'd2 || pc_after[9:6]==4'd3)
                        PC <= {pc_after[9:7], op[6:0]};          // JP páginas 2/3 (7-bit)
                    else if(op[7:6]==2'b11)
                        PC <= {pc_after[9:6], op[5:0]};          // JP 0xC0-0xFF (6-bit)
                    else
                        PC <= {pc_after[9:7], op[6:0]};          // JP normal
                end
                // ===== prefijo 0x23 (LDD / XAD) =====
                8'h23: begin
                    if(operand <= 8'h57) A <= ram[operand[5:0]];                 // LDD
                    else begin ram[operand[5:0]] <= A; A <= ram[operand[5:0]]; end // XAD (swap)
                end
                // ===== prefijo 0x33 (I/O del AY + bit-ops G) =====
                8'h33: begin
                    casez (operand)
                    8'h01: if(!g_out[0]) do_skip=1;          // SKGBZ0
                    8'h11: if(!g_out[1]) do_skip=1;          // SKGBZ1
                    8'h03: if(!g_out[2]) do_skip=1;          // SKGBZ2
                    8'h13: if(!g_out[3]) do_skip=1;          // SKGBZ3
                    8'h21: if(g_out==0) do_skip=1;           // SKGZ
                    8'h28: A <= in_in;                       // ININ (A<-IN)
                    8'h2A: A <= g_out;                       // ING  (A<-G)
                    8'h2C: begin ram[B]<=Q[7:4]; A<=Q[3:0]; end // CQMA
                    8'h2E: begin ram[B]<=l_in[7:4]; A<=l_in[3:0]; end // INL
                    8'h3A: begin g_out<=rb; end              // OMG (G<-RAM)
                    8'h3C: begin Q<={A,rb}; q_out<={A,rb}; if(EN[2]) l_out<={A,rb}; end // CAMQ (Q<-A,RAM)
                    8'h3E: d_out <= B[3:0];                  // OBD (D<-Bd)
                    8'b0101_????: g_out<=operand[3:0];       // OGI (G<-y)  0x50-0x5F
                    8'b0110_????: begin                      // LEI (EN<-y) 0x60-0x6F
                        EN<=operand[3:0]; if(operand[2]) begin l_out<=Q; end
                    end
                    8'b1???_????: begin                      // LBI largo (0x80-0xBF): B<-operand&0x7f
                        skip_lbi<=2'd2; B<=operand[5:0];
                    end
                    default: ;
                    endcase
                end
                default: ;
                endcase

                if (do_skip) skip <= 1'b1;
                last_skip <= skip;
            end
        end
    end
endmodule

`default_nettype wire
