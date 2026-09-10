`timescale 1ns/1ps
`default_nettype none

module cop402_jl (
    input  wire        clk,
    input  wire        ce,
    input  wire        reset,

    input  wire [3:0]  in_in,
    input  wire [7:0]  l_in,
    output reg  [3:0]  g_out,
    output reg  [7:0]  q_out,
    output reg  [3:0]  d_out,
    output reg  [7:0]  l_out,
    output wire        sk_out,

    output wire [9:0]  dbg_pc,
    output wire [3:0]  dbg_a,
    output wire [5:0]  dbg_b,
    output wire [3:0]  dbg_g,
    output wire [7:0]  dbg_q,
    output wire [3:0]  dbg_en,
    output wire        dbg_skip,

    input  wire        ioctl_rom_we,
    input  wire [10:0] ioctl_rom_addr,
    input  wire [7:0]  ioctl_rom_data
);

    (* ramstyle = "MLAB, no_rw_check" *) reg [7:0] rom [0:2047];
`ifdef SIM
    initial $readmemh("../../roms/draco_sound.hex", rom);
`endif
    always @(posedge clk) if (ioctl_rom_we) rom[ioctl_rom_addr] <= ioctl_rom_data;

    reg [3:0] ram [0:63];

    reg [9:0] PC;
    reg [3:0] A;
    reg [5:0] B;
    reg       C;
    reg [3:0] EN;
    reg [7:0] Q;
    reg [9:0] SA, SB, SC;
    reg [3:0] SIO;
    reg [7:0] T;
    reg       SKL;
    reg       skt_latch;
    reg [2:0] tcyc;
    reg       skip;
    reg [1:0] skip_lbi;
    reg       last_skip;

    assign dbg_pc=PC; assign dbg_a=A; assign dbg_b=B; assign dbg_g=g_out;
    assign dbg_q=Q; assign dbg_en=EN; assign dbg_skip=skip;
    assign sk_out = (~EN[0]) ? SKL : C;

    function is2(input [7:0] op);
        is2 = (op==8'h33) || (op==8'h23) ||
              (op>=8'h60 && op<=8'h63) || (op>=8'h68 && op<=8'h6B);
    endfunction

    reg [7:0] op2;
    reg [4:0] add5;
    reg [3:0] ynib;
    reg       do_skip;

    wire [7:0] op           = rom[{d_out[3], PC}];
    wire [9:0] pc_after     = PC + (is2(op) ? 10'd2 : 10'd1);
    wire [3:0] rb           = ram[B];
    wire [9:0] jaddr        = {pc_after[9:8], A, ram[B]};

    wire [9:0] operand_addr = (op==8'hBF || op==8'hFF) ? jaddr : (PC + 10'd1);
    wire [7:0] operand      = rom[{d_out[3], operand_addr}];

    always @(posedge clk) begin
        if (reset) begin
            PC<=0; A<=0; B<=0; C<=0; EN<=0; Q<=0; SA<=0; SB<=0; SC<=0; SIO<=0; T<=0;
            SKL<=1; skt_latch<=0; tcyc=0; skip<=0; skip_lbi<=0; last_skip<=0;
            g_out<=0; q_out<=0; d_out<=0; l_out<=0;
        end else if (ce) begin
            do_skip  = 1'b0;

            tcyc = tcyc + (is2(op) ? 3'd2 : 3'd1);
            if (tcyc >= 3'd4) begin
                tcyc = tcyc - 3'd4;
                T <= T + 8'd1;
                if (T == 8'hFF) skt_latch <= 1'b1;
            end

            if (skip) begin

                skip <= 1'b0;
                PC   <= pc_after;
            end else begin
                PC <= pc_after;
                if (skip_lbi != 0) skip_lbi <= skip_lbi - 2'd1;

                casez (op)

                8'h00: A <= 4'd0;
                8'h02: A <= A ^ rb;
                8'h10: begin add5=(A^4'hF)+rb+C; A<=add5[3:0]; if(add5[4]) begin C<=1; do_skip=1; end else C<=0; end
                8'h12: begin A <= {2'd0,B[5:4]}; B <= {A[1:0],B[3:0]}; end
                8'h20: if(C) do_skip=1;
                8'h21: if(A==rb) do_skip=1;
                8'h22: C <= 1'b1;
                8'h30: begin add5=A+C+rb; A<=add5[3:0]; if(add5[4]) begin C<=1; do_skip=1; end else C<=0; end
                8'h31: A <= A + rb;
                8'h32: C <= 1'b0;
                8'h40: A <= A ^ 4'hF;
                8'h41: if(skt_latch) begin skt_latch<=0; do_skip=1; end
                8'h42: ram[B] <= rb & 4'hB;
                8'h43: ram[B] <= rb & 4'h7;
                8'h44: ;
                8'h45: ram[B] <= rb & 4'hD;
                8'h46: ram[B] <= rb | 4'h4;
                8'h47: ram[B] <= rb | 4'h2;
                8'h48: begin PC<=SA; SA<=SB; SB<=SC; skip<=last_skip; end
                8'h49: begin PC<=SA; SA<=SB; SB<=SC; do_skip=1; end
                8'h4A: A <= A + 4'd10;
                8'h4B: ram[B] <= rb | 4'h8;
                8'h4C: ram[B] <= rb & 4'hE;
                8'h4D: ram[B] <= rb | 4'h1;
                8'h4E: A <= B[3:0];
                8'h4F: begin SIO<=A; A<=SIO; SKL<=C; end
                8'h50: B <= {B[5:4], A};

                8'h01: if(!rb[0]) do_skip=1;
                8'h11: if(!rb[1]) do_skip=1;
                8'h03: if(!rb[2]) do_skip=1;
                8'h13: if(!rb[3]) do_skip=1;

                8'b0101_????: begin add5=A+op[3:0]; A<=add5[3:0]; if(add5[4]) do_skip=1; end
                8'b00??_1???: begin B <= {op[5:4], (op[3:0]+4'd1)}; end
                8'b00??_0101: begin A<=rb; B<=B ^ {op[5:4],4'd0}; end
                8'b00??_0110: begin ram[B]<=A; A<=rb; B<=B ^ {op[5:4],4'd0}; end
                8'b00??_0100: begin ram[B]<=A; A<=rb; B<={B[5:4]^op[5:4],(B[3:0]+4'd1)}; if(B[3:0]==4'hF) do_skip=1; end
                8'b00??_0111: begin ram[B]<=A; A<=rb; B<={B[5:4]^op[5:4],(B[3:0]-4'd1)}; if(B[3:0]==4'h0) do_skip=1; end
                8'b0111_????: begin ram[B]<=op[3:0]; B<={B[5:4],(B[3:0]+4'd1)}; end
                8'b0110_0_0??: PC <= (({op[2:0],operand}) & 10'h3ff);
                8'b0110_1_0??: begin SC<=SB; SB<=SA; SA<=pc_after; PC <= (({op[2:0],operand}) & 10'h3ff); end

                8'b1???_????: begin
                    if(op==8'hBF) begin
                        SC<=SB; SB<=SA; SA<=pc_after;

                        Q <= operand; if(EN[2]) l_out<=operand; q_out<=operand;
                        PC <= pc_after;
                    end else if(op==8'hFF) begin
                        op2 = operand;
                        PC <= {jaddr[9:8], op2};
                    end else if(pc_after[9:6]==4'd2 || pc_after[9:6]==4'd3)
                        PC <= {pc_after[9:7], op[6:0]};
                    else if(op[7:6]==2'b11)
                        PC <= {pc_after[9:6], op[5:0]};
                    else
                        PC <= {pc_after[9:7], op[6:0]};
                end

                8'h23: begin
                    if(operand <= 8'h57) A <= ram[operand[5:0]];
                    else begin ram[operand[5:0]] <= A; A <= ram[operand[5:0]]; end
                end

                8'h33: begin
                    casez (operand)
                    8'h01: if(!g_out[0]) do_skip=1;
                    8'h11: if(!g_out[1]) do_skip=1;
                    8'h03: if(!g_out[2]) do_skip=1;
                    8'h13: if(!g_out[3]) do_skip=1;
                    8'h21: if(g_out==0) do_skip=1;
                    8'h28: A <= in_in;
                    8'h2A: A <= g_out;
                    8'h2C: begin ram[B]<=Q[7:4]; A<=Q[3:0]; end
                    8'h2E: begin ram[B]<=l_in[7:4]; A<=l_in[3:0]; end
                    8'h3A: begin g_out<=rb; end
                    8'h3C: begin Q<={A,rb}; q_out<={A,rb}; if(EN[2]) l_out<={A,rb}; end
                    8'h3E: d_out <= B[3:0];
                    8'b0101_????: g_out<=operand[3:0];
                    8'b0110_????: begin
                        EN<=operand[3:0]; if(operand[2]) begin l_out<=Q; end
                    end
                    8'b1???_????: begin
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
