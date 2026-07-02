// ============================================================================
//  cdp1802_jl — CPU RCA CDP1802 (COSMAC) en Verilog, escrita desde cero.
// ----------------------------------------------------------------------------
//  Traducción directa de los handlers de MAME (reference/mame/cosmac.cpp).
//  Granularidad de CICLO DE MÁQUINA: cada pulso de ce avanza un ciclo
//  (FETCH / EXECUTE / EXECUTE2 / INT). Memoria ASÍNCRONA (data_in = mem[addr]
//  combinacional, como espera el resto del sistema).
//
//  Interfaz compatible con cidelsa_machine (mismos nombres que cosmac.v):
//    clk, clk_enable(=ce), clear(reset activo-alto), int_req, ef[4:1],
//    data_in, data_out, address, mem_read, mem_write, io_port, q_out, sc.
//  OUT vs INP: el sistema lo distingue por mem_read (OUT lee M(R(X))) vs
//  mem_write (INP escribe M(R(X))). Payload OUT3=data_in; OUT4-7=address(=R(X)).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module cdp1802_jl (
    input  wire        clk,
    input  wire        clk_enable,
    input  wire        clear,          // reset activo-alto
    input  wire        dma_in_req,     // (no usado en Cidelsa)
    input  wire        dma_out_req,
    input  wire        int_req,        // interrupción (activo-alto)
    input  wire        wait_req,       // (no usado: 0)
    input  wire [4:1]  ef,             // EF1..EF4
    input  wire [7:0]  data_in,        // M(addr) (async) / valor de I/O en INP
    output reg  [7:0]  data_out,       // dato a escribir en memoria
    output wire [15:0] address,        // bus de direcciones
    output reg         mem_read,
    output reg         mem_write,
    output reg  [2:0]  io_port,        // N (1..7) en OUT/INP; 0 si no hay I/O
    output wire        q_out,
    output reg  [1:0]  sc,             // state code (00=fetch,01=exec,11=int)
    // debug
    output wire [15:0] dbg_pc,
    output wire [15:0] dbg_r11,
    output wire [2:0]  dbg_state,
    output wire [7:0]  dbg_op,
    output wire [15:0] dbg_r1,
    output wire [3:0]  dbg_p,
    output wire [3:0]  dbg_x,
    output wire [7:0]  dbg_d_out
);
    assign dbg_r1 = R[4'd1];
    assign dbg_p  = P;
    assign dbg_x  = X;
    assign dbg_d_out = D;
    // ---- registros de estado ----
    reg [15:0] R [0:15];
    reg [3:0]  P, X;
    reg [7:0]  D, T, B;
    reg        DF, IE, Q;
    reg [7:0]  op;            // opcode actual
    reg [2:0]  state;

    localparam ST_FETCH = 3'd0, ST_EXEC = 3'd1, ST_EXEC2 = 3'd2, ST_INT = 3'd3;

    wire [3:0] I = op[7:4];
    wire [3:0] N = op[3:0];
    assign q_out  = Q;
    assign dbg_pc = R[P];
    assign dbg_r11 = R[4'd11];
    assign dbg_state = state;
    assign dbg_op    = op;

    // ---- selección de dirección y acceso a memoria (combinacional) ----
    reg [3:0]  addr_sel;     // qué registro va al bus
    localparam AS_P = 4'd0, AS_X = 4'd1, AS_N = 4'd2, AS_2 = 4'd3;
    reg [15:0] addr_r;
    always @(*) begin
        case (addr_sel)
            AS_P:    addr_r = R[P];
            AS_X:    addr_r = R[X];
            AS_N:    addr_r = R[N];
            default: addr_r = R[2];
        endcase
    end
    assign address = addr_r;

    // operando leído de memoria (async)
    wire [7:0] M = data_in;

    // ---- ALU (suma/resta estilo MAME: result9 = a + b9; DF = result>0xff) ----
    // add(l,r): l+r ; sub(l,r): l + (~r) + 1 ; sbc: l + (~r) + DF ; adc: l+r+DF
    function [8:0] alu_add; input [7:0] l; input [7:0] r; input cin;
        alu_add = {1'b0,l} + {1'b0,r} + {8'd0,cin};
    endfunction
    function [8:0] alu_sub; input [7:0] l; input [7:0] r; input cin; // cin=1 normal, =DF para borrow
        alu_sub = {1'b0,l} + {1'b0,(~r)} + {8'd0,cin};
    endfunction

    // ---- condición de rama corta/larga ----
    reg cond;
    always @(*) begin
        // N[2:0]: 0=incond,1=Q,2=Z,3=DF,4..7=EF1..4 ; N[3]=invierte
        case (N[2:0])
            3'd0: cond = 1'b1;
            3'd1: cond = Q;
            3'd2: cond = (D == 8'd0);
            3'd3: cond = DF;
            3'd4: cond = ef[1];
            3'd5: cond = ef[2];
            3'd6: cond = ef[3];
            default: cond = ef[4];
        endcase
    end
    wire take = cond ^ N[3];   // BNx = invierte (ramas cortas y largas)

    // long skips (grupo C): condición y distinción branch/skip
    //  branch: C0-C3,C9-CB (N[2]=0, N!=8) ; skip: C4-C7,C8,CC-CF
    wire is_skip = N[2] | (N == 4'h8);
    wire cond_lo = (N[1:0]==2'd1) ? Q : (N[1:0]==2'd2) ? (D==8'd0) : DF;
    wire take_sk = (N==4'h8) ? 1'b1 :              // C8 LSKP/NLBR: siempre
                   (N==4'h4) ? 1'b0 :              // C4 NOP: nunca
                   (~N[3])   ? ~cond_lo :          // C5 LSNQ, C6 LSNZ, C7 LSNF
                   (N[1:0]==2'd0) ? IE : cond_lo;  // CC LSIE, CD LSQ, CE LSZ, CF LSDF

    // ---- lógica combinacional de ejecución: calcula los "next" ----
    reg [2:0]  nstate;
    reg [3:0]  np, nx;
    reg [7:0]  nd, nt, nb;
    reg        ndf, nie, nq;
    // escritura al register file (granularidad de byte)
    reg        rf_we_lo, rf_we_hi;
    reg [3:0]  rf_sel;
    reg [7:0]  rf_lo, rf_hi;
    reg [8:0]  alu;

    task wr16; input [3:0] s; input [15:0] v; begin
        rf_sel=s; rf_lo=v[7:0]; rf_hi=v[15:8]; rf_we_lo=1'b1; rf_we_hi=1'b1;
    end endtask

    always @(*) begin
        // defaults: mantener todo
        nstate = ST_FETCH;
        np=P; nx=X; nd=D; nt=T; nb=B; ndf=DF; nie=IE; nq=Q;
        rf_we_lo=1'b0; rf_we_hi=1'b0; rf_sel=4'd0; rf_lo=8'd0; rf_hi=8'd0;
        addr_sel=AS_P; mem_read=1'b0; mem_write=1'b0; data_out=D; io_port=3'd0;
        sc=2'b01; alu=9'd0;

        case (state)
        // -------------------------------------------------- FETCH
        ST_FETCH: begin
            sc=2'b00; addr_sel=AS_P; mem_read=1'b1;
            // op <= M ; R[P]++   (se hace en el bloque secuencial)
            nstate = ST_EXEC;
        end
        // -------------------------------------------------- EXECUTE
        ST_EXEC: begin
            sc=2'b01;
            casez (I)
            4'h0: begin // LDN (N!=0): D=M(R[N]) ; 00=IDL
                if (N!=4'd0) begin addr_sel=AS_N; mem_read=1'b1; nd=M; end
            end
            4'h1: begin wr16(N, R[N]+16'd1); end                 // INC
            4'h2: begin wr16(N, R[N]-16'd1); end                 // DEC
            4'h3: begin // short branch
                addr_sel=AS_P; mem_read=1'b1;
                if (take) begin rf_sel=P; rf_lo=M; rf_we_lo=1'b1; end // R[P].lo = M
                else      begin wr16(P, R[P]+16'd1); end              // skip operand
            end
            4'h4: begin addr_sel=AS_N; mem_read=1'b1; nd=M; wr16(N, R[N]+16'd1); end // LDA
            4'h5: begin addr_sel=AS_N; mem_write=1'b1; data_out=D; end               // STR
            4'h6: begin // 60=IRX, 61-67=OUT, 69-6F=INP
                if (N==4'd0) begin wr16(X, R[X]+16'd1); end                       // IRX
                else if (N[3]==1'b0) begin // OUT n
                    addr_sel=AS_X; mem_read=1'b1; io_port=N[2:0];
                    wr16(X, R[X]+16'd1);                                          // R[X]++
                end else begin // INP n
                    addr_sel=AS_X; mem_write=1'b1; io_port=N[2:0];
                    nd=M; data_out=M;     // D=io ; M(R[X])=io  (machine mete io en data_in)
                end
            end
            4'h7: begin
                case (N)
                4'h0,4'h1: begin // RET(70)/DIS(71): D=M(R[X]); R[X]++; P=lo; X=hi; IE
                    addr_sel=AS_X; mem_read=1'b1;
                    np=M[3:0]; nx=M[7:4]; nie=(N==4'd0)?1'b1:1'b0;
                    wr16(X, R[X]+16'd1);
                end
                4'h2: begin addr_sel=AS_X; mem_read=1'b1; nd=M; wr16(X, R[X]+16'd1); end // LDXA
                4'h3: begin addr_sel=AS_X; mem_write=1'b1; data_out=D; wr16(X, R[X]-16'd1); end // STXD
                4'h4: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_add(M,D,DF); nd=alu[7:0]; ndf=alu[8]; end // ADC
                4'h5: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_sub(M,D,DF); nd=alu[7:0]; ndf=alu[8]; end // SDB
                4'h6: begin ndf=D[0]; nd={DF,D[7:1]}; end                         // 76=SHRC/RSHR: D=(D>>1)|(DF<<7), DF=old D[0]
                4'h7: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_sub(D,M,DF); nd=alu[7:0]; ndf=alu[8]; end // SMB
                4'h8: begin addr_sel=AS_X; mem_write=1'b1; data_out=T; end          // SAV: M(R[X])=T
                4'h9: begin // MARK: T=(X<<4)|P; M(R[2])=T; X=P; R[2]--
                    nt={X,P}; addr_sel=AS_2; mem_write=1'b1; data_out={X,P};
                    nx=P; wr16(4'd2, R[2]-16'd1);
                end
                4'ha: begin nq=1'b0; end                                          // REQ
                4'hb: begin nq=1'b1; end                                          // SEQ
                4'hc: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_add(M,D,DF); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end // ADCI
                4'hd: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_sub(M,D,DF); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end // SDBI
                4'he: begin ndf=D[7]; nd={D[6:0],DF}; end                         // 7E=SHLC/RSHL: D=(D<<1)|DF, DF=old D[7]
                4'hf: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_sub(D,M,DF); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end // SMBI
                endcase
            end
            4'h8: begin nd = R[N][7:0]; end                       // GLO
            4'h9: begin nd = R[N][15:8]; end                      // GHI
            4'ha: begin rf_sel=N; rf_lo=D; rf_we_lo=1'b1; end     // PLO
            4'hb: begin rf_sel=N; rf_hi=D; rf_we_hi=1'b1; end     // PHI
            4'hc: begin // grupo C: long branch (2 bytes operando) o long skip (sin operando) -> S1#1
                addr_sel=AS_P; mem_read=1'b1;
                if (!is_skip) begin nb=M; wr16(P, R[P]+16'd1); end   // branch: B=M(hi); R[P]++
                else if (take_sk) begin wr16(P, R[P]+16'd1); end      // skip tomado: R[P]++ (1 de 2)
                nstate = ST_EXEC2;
            end
            4'hd: begin np = N; end                               // SEP
            4'he: begin nx = N; end                               // SEX
            4'hf: begin
                case (N)
                4'h0: begin addr_sel=AS_X; mem_read=1'b1; nd=M; end                // LDX
                4'h1: begin addr_sel=AS_X; mem_read=1'b1; nd=M|D; end              // OR
                4'h2: begin addr_sel=AS_X; mem_read=1'b1; nd=M&D; end              // AND
                4'h3: begin addr_sel=AS_X; mem_read=1'b1; nd=M^D; end              // XOR
                4'h4: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_add(M,D,1'b0); nd=alu[7:0]; ndf=alu[8]; end // ADD
                4'h5: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_sub(M,D,1'b1); nd=alu[7:0]; ndf=alu[8]; end // SD = M-D
                4'h6: begin ndf=D[0]; nd={1'b0,D[7:1]}; end                        // SHR
                4'h7: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_sub(D,M,1'b1); nd=alu[7:0]; ndf=alu[8]; end // SM = D-M
                4'h8: begin addr_sel=AS_P; mem_read=1'b1; nd=M; wr16(P,R[P]+16'd1); end // LDI
                4'h9: begin addr_sel=AS_P; mem_read=1'b1; nd=M|D; wr16(P,R[P]+16'd1); end // ORI
                4'ha: begin addr_sel=AS_P; mem_read=1'b1; nd=M&D; wr16(P,R[P]+16'd1); end // ANI
                4'hb: begin addr_sel=AS_P; mem_read=1'b1; nd=M^D; wr16(P,R[P]+16'd1); end // XRI
                4'hc: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_add(M,D,1'b0); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end // ADI
                4'hd: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_sub(M,D,1'b1); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end // SDI = M-D
                4'he: begin ndf=D[7]; nd={D[6:0],1'b0}; end                        // SHL
                4'hf: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_sub(D,M,1'b1); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end // SMI = D-M
                endcase
            end
            endcase

            // siguiente estado tras EXEC (si no es 0xC que ya puso EXEC2)
            if (I != 4'hc) begin
                if (nie & int_req) nstate = ST_INT;
                else if (op==8'h00) nstate = ST_EXEC;  // IDL: se queda
                else                nstate = ST_FETCH;
            end
        end
        // -------------------------------------------------- EXECUTE2 (long, 2º byte)
        ST_EXEC2: begin   // grupo C, segundo ciclo
            sc=2'b01; addr_sel=AS_P; mem_read=1'b1;
            if (!is_skip) begin
                // LONG BRANCH: si tomada R[P]={B,M}; si no, saltar 2º byte (R[P]++)
                if (take) begin wr16(P, {B, M}); end
                else      begin wr16(P, R[P]+16'd1); end
            end else begin
                // LONG SKIP: si tomado, R[P]++ (2º incremento -> +2 total, salta los 2 bytes siguientes)
                if (take_sk) begin wr16(P, R[P]+16'd1); end
            end
            if (nie & int_req) nstate = ST_INT; else nstate = ST_FETCH;
        end
        // -------------------------------------------------- INTERRUPT
        ST_INT: begin
            sc=2'b11;
            nt={X,P}; np=4'd1; nx=4'd2; nie=1'b0;
            nstate = ST_FETCH;
        end
        endcase
    end

    // ---- bloque secuencial: aplica los "next" en ce ----
    integer k;
    always @(posedge clk) begin
        if (clear) begin
            P<=4'd0; X<=4'd0; D<=8'd0; DF<=1'b0; IE<=1'b1; Q<=1'b0;
            T<=8'd0; B<=8'd0; op<=8'd0; state<=ST_FETCH;
            R[0]<=16'd0;
        end else if (clk_enable) begin
            state <= nstate;
            // fetch: latch opcode + R[P]++
            if (state==ST_FETCH) begin
                op <= M;
                R[P] <= R[P] + 16'd1;
            end else begin
                // register file write (byte-granular)
                if (rf_we_lo) R[rf_sel][7:0]  <= rf_lo;
                if (rf_we_hi) R[rf_sel][15:8] <= rf_hi;
            end
            P<=np; X<=nx; D<=nd; T<=nt; B<=nb; DF<=ndf; IE<=nie; Q<=nq;
        end
    end

`ifdef SIM
    integer j;
    initial for (j=0;j<16;j=j+1) R[j]=16'd0;
`endif
endmodule

`default_nettype wire
