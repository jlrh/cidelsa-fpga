`timescale 1ns/1ps
`default_nettype none

module cdp1802_jl (
    input  wire        clk,
    input  wire        clk_enable,
    input  wire        clear,
    input  wire        dma_in_req,
    input  wire        dma_out_req,
    input  wire        int_req,
    input  wire        wait_req,
    input  wire [4:1]  ef,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    output wire [15:0] address,
    output reg         mem_read,
    output reg         mem_write,
    output reg  [2:0]  io_port,
    output wire        q_out,
    output reg  [1:0]  sc,

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

    reg [15:0] R [0:15];
    reg [3:0]  P, X;
    reg [7:0]  D, T, B;
    reg        DF, IE, Q;
    reg [7:0]  op;
    reg [2:0]  state;

    localparam ST_FETCH = 3'd0, ST_EXEC = 3'd1, ST_EXEC2 = 3'd2, ST_INT = 3'd3;

    wire [3:0] I = op[7:4];
    wire [3:0] N = op[3:0];
    assign q_out  = Q;
    assign dbg_pc = R[P];
    assign dbg_r11 = R[4'd11];
    assign dbg_state = state;
    assign dbg_op    = op;

    reg [3:0]  addr_sel;
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

    wire [7:0] M = data_in;

    function [8:0] alu_add; input [7:0] l; input [7:0] r; input cin;
        alu_add = {1'b0,l} + {1'b0,r} + {8'd0,cin};
    endfunction
    function [8:0] alu_sub; input [7:0] l; input [7:0] r; input cin;
        alu_sub = {1'b0,l} + {1'b0,(~r)} + {8'd0,cin};
    endfunction

    reg cond;
    always @(*) begin

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
    wire take = cond ^ N[3];

    wire is_skip = N[2] | (N == 4'h8);
    wire cond_lo = (N[1:0]==2'd1) ? Q : (N[1:0]==2'd2) ? (D==8'd0) : DF;
    wire take_sk = (N==4'h8) ? 1'b1 :
                   (N==4'h4) ? 1'b0 :
                   (~N[3])   ? ~cond_lo :
                   (N[1:0]==2'd0) ? IE : cond_lo;

    reg [2:0]  nstate;
    reg [3:0]  np, nx;
    reg [7:0]  nd, nt, nb;
    reg        ndf, nie, nq;

    reg        rf_we_lo, rf_we_hi;
    reg [3:0]  rf_sel;
    reg [7:0]  rf_lo, rf_hi;
    reg [8:0]  alu;

    task wr16; input [3:0] s; input [15:0] v; begin
        rf_sel=s; rf_lo=v[7:0]; rf_hi=v[15:8]; rf_we_lo=1'b1; rf_we_hi=1'b1;
    end endtask

    always @(*) begin

        nstate = ST_FETCH;
        np=P; nx=X; nd=D; nt=T; nb=B; ndf=DF; nie=IE; nq=Q;
        rf_we_lo=1'b0; rf_we_hi=1'b0; rf_sel=4'd0; rf_lo=8'd0; rf_hi=8'd0;
        addr_sel=AS_P; mem_read=1'b0; mem_write=1'b0; data_out=D; io_port=3'd0;
        sc=2'b01; alu=9'd0;

        case (state)

        ST_FETCH: begin
            sc=2'b00; addr_sel=AS_P; mem_read=1'b1;

            nstate = ST_EXEC;
        end

        ST_EXEC: begin
            sc=2'b01;
            casez (I)
            4'h0: begin
                if (N!=4'd0) begin addr_sel=AS_N; mem_read=1'b1; nd=M; end
            end
            4'h1: begin wr16(N, R[N]+16'd1); end
            4'h2: begin wr16(N, R[N]-16'd1); end
            4'h3: begin
                addr_sel=AS_P; mem_read=1'b1;
                if (take) begin rf_sel=P; rf_lo=M; rf_we_lo=1'b1; end
                else      begin wr16(P, R[P]+16'd1); end
            end
            4'h4: begin addr_sel=AS_N; mem_read=1'b1; nd=M; wr16(N, R[N]+16'd1); end
            4'h5: begin addr_sel=AS_N; mem_write=1'b1; data_out=D; end
            4'h6: begin
                if (N==4'd0) begin wr16(X, R[X]+16'd1); end
                else if (N[3]==1'b0) begin
                    addr_sel=AS_X; mem_read=1'b1; io_port=N[2:0];
                    wr16(X, R[X]+16'd1);
                end else begin
                    addr_sel=AS_X; mem_write=1'b1; io_port=N[2:0];
                    nd=M; data_out=M;
                end
            end
            4'h7: begin
                case (N)
                4'h0,4'h1: begin
                    addr_sel=AS_X; mem_read=1'b1;
                    np=M[3:0]; nx=M[7:4]; nie=(N==4'd0)?1'b1:1'b0;
                    wr16(X, R[X]+16'd1);
                end
                4'h2: begin addr_sel=AS_X; mem_read=1'b1; nd=M; wr16(X, R[X]+16'd1); end
                4'h3: begin addr_sel=AS_X; mem_write=1'b1; data_out=D; wr16(X, R[X]-16'd1); end
                4'h4: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_add(M,D,DF); nd=alu[7:0]; ndf=alu[8]; end
                4'h5: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_sub(M,D,DF); nd=alu[7:0]; ndf=alu[8]; end
                4'h6: begin ndf=D[0]; nd={DF,D[7:1]}; end
                4'h7: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_sub(D,M,DF); nd=alu[7:0]; ndf=alu[8]; end
                4'h8: begin addr_sel=AS_X; mem_write=1'b1; data_out=T; end
                4'h9: begin
                    nt={X,P}; addr_sel=AS_2; mem_write=1'b1; data_out={X,P};
                    nx=P; wr16(4'd2, R[2]-16'd1);
                end
                4'ha: begin nq=1'b0; end
                4'hb: begin nq=1'b1; end
                4'hc: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_add(M,D,DF); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end
                4'hd: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_sub(M,D,DF); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end
                4'he: begin ndf=D[7]; nd={D[6:0],DF}; end
                4'hf: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_sub(D,M,DF); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end
                endcase
            end
            4'h8: begin nd = R[N][7:0]; end
            4'h9: begin nd = R[N][15:8]; end
            4'ha: begin rf_sel=N; rf_lo=D; rf_we_lo=1'b1; end
            4'hb: begin rf_sel=N; rf_hi=D; rf_we_hi=1'b1; end
            4'hc: begin
                addr_sel=AS_P; mem_read=1'b1;
                if (!is_skip) begin nb=M; wr16(P, R[P]+16'd1); end
                else if (take_sk) begin wr16(P, R[P]+16'd1); end
                nstate = ST_EXEC2;
            end
            4'hd: begin np = N; end
            4'he: begin nx = N; end
            4'hf: begin
                case (N)
                4'h0: begin addr_sel=AS_X; mem_read=1'b1; nd=M; end
                4'h1: begin addr_sel=AS_X; mem_read=1'b1; nd=M|D; end
                4'h2: begin addr_sel=AS_X; mem_read=1'b1; nd=M&D; end
                4'h3: begin addr_sel=AS_X; mem_read=1'b1; nd=M^D; end
                4'h4: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_add(M,D,1'b0); nd=alu[7:0]; ndf=alu[8]; end
                4'h5: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_sub(M,D,1'b1); nd=alu[7:0]; ndf=alu[8]; end
                4'h6: begin ndf=D[0]; nd={1'b0,D[7:1]}; end
                4'h7: begin addr_sel=AS_X; mem_read=1'b1; alu=alu_sub(D,M,1'b1); nd=alu[7:0]; ndf=alu[8]; end
                4'h8: begin addr_sel=AS_P; mem_read=1'b1; nd=M; wr16(P,R[P]+16'd1); end
                4'h9: begin addr_sel=AS_P; mem_read=1'b1; nd=M|D; wr16(P,R[P]+16'd1); end
                4'ha: begin addr_sel=AS_P; mem_read=1'b1; nd=M&D; wr16(P,R[P]+16'd1); end
                4'hb: begin addr_sel=AS_P; mem_read=1'b1; nd=M^D; wr16(P,R[P]+16'd1); end
                4'hc: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_add(M,D,1'b0); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end
                4'hd: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_sub(M,D,1'b1); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end
                4'he: begin ndf=D[7]; nd={D[6:0],1'b0}; end
                4'hf: begin addr_sel=AS_P; mem_read=1'b1; alu=alu_sub(D,M,1'b1); nd=alu[7:0]; ndf=alu[8]; wr16(P,R[P]+16'd1); end
                endcase
            end
            endcase

            if (I != 4'hc) begin
                if (nie & int_req) nstate = ST_INT;
                else if (op==8'h00) nstate = ST_EXEC;
                else                nstate = ST_FETCH;
            end
        end

        ST_EXEC2: begin
            sc=2'b01; addr_sel=AS_P; mem_read=1'b1;
            if (!is_skip) begin

                if (take) begin wr16(P, {B, M}); end
                else      begin wr16(P, R[P]+16'd1); end
            end else begin

                if (take_sk) begin wr16(P, R[P]+16'd1); end
            end
            if (nie & int_req) nstate = ST_INT; else nstate = ST_FETCH;
        end

        ST_INT: begin
            sc=2'b11;
            nt={X,P}; np=4'd1; nx=4'd2; nie=1'b0;
            nstate = ST_FETCH;
        end
        endcase
    end

    integer k;
    always @(posedge clk) begin
        if (clear) begin
            P<=4'd0; X<=4'd0; D<=8'd0; DF<=1'b0; IE<=1'b1; Q<=1'b0;
            T<=8'd0; B<=8'd0; op<=8'd0; state<=ST_FETCH;
            R[0]<=16'd0;
        end else if (clk_enable) begin
            state <= nstate;

            if (state==ST_FETCH) begin
                op <= M;
                R[P] <= R[P] + 16'd1;
            end else begin

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
