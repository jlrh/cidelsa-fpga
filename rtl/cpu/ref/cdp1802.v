//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

`default_nettype none
/* verilator lint_off UNOPTFLAT */

module cdp1802 (
  input               CLOCK,
  input               CLEAR_N,

  output reg          Q,
  input      [3:0]    EF,

  input               WAIT_N,
  input               INT_N,
  input               dma_in_req,
  input               dma_out_req,
  output reg [1:0]    SC,

  input      [7:0]    io_din,
  output     [7:0]    io_dout,
  output     [2:0]    io_n,
  output  wire        io_inp,
  output  wire        io_out,

  output              unsupported,

  output              ram_rd,
  output              ram_wr,
  output     [15:0]   ram_a,
  input      [7:0]    ram_q,
  output     [7:0]    ram_d

);

  reg   IE;

  reg [3:0] state, state_n = 4'd0;

  localparam RESET     = 4'd0;
  localparam FETCH     = 4'd1;
  localparam EXECUTE   = 4'd2;
  localparam EXECUTE2  = 4'd3;
  localparam BRANCH2   = 4'd4;
  localparam BRANCH3   = 4'd5;
  localparam SKIP      = 4'd6;

  localparam DMA_IN    = 4'd7;
  localparam DMA_OUT   = 4'd8;
  localparam INTERRUPT = 4'd9;

  reg   [3:0] P;
  reg   [3:0] X;
  reg   [7:0] T;

  reg  [15:0] R[0:15];
  wire  [3:0] Ra;
  wire [15:0] Rrd = R[Ra];
  reg  [15:0] Rwd;

  reg   [7:0] D;
  reg         DF;
  reg   [7:0] B;
  reg   [7:0] ram_q_;
  wire  [3:0] I, N;

  assign ram_d = (I == 4'h6) ? io_din : D;
  assign ram_a = Rrd;

  reg sense;
  always @*
    casez ({I, N})
      {4'h3, 4'b?000}, {4'hc, 4'b??00}: sense = 1;
      {4'h3, 4'b?001}, {4'hc, 4'b??01}: sense = Q;
      {4'h3, 4'b?010}, {4'hc, 4'b??10}: sense = (D == 8'h00);
      {4'h3, 4'b?011}, {4'hc, 4'b??11}: sense = DF;
      {4'h3, 4'b?1??}:                  sense = EF[N[1:0]];
      default:                          sense = 1'bx;
    endcase
  wire take = sense ^ N[3];

  always @*
    case (state)
    FETCH: begin
      SC <= 2'b00;

      state_n = EXECUTE;
    end
    EXECUTE: begin
      SC <= 2'b01;

        case (I)
          4'h3:     state_n = take ? BRANCH3 : FETCH;
          4'hc:     state_n = take ? BRANCH2 : SKIP;
          default:  state_n = ram_rd ? EXECUTE2 : FETCH;
        endcase

    end
    BRANCH2: begin
      $display("state_n BRANCH2");
      state_n = BRANCH3;
    end
    DMA_IN: begin
      $display("state_n DMA_IN");
      SC <= 2'b10;
    end
    DMA_OUT: begin
      $display("state_n DMA_OUT");
      SC <= 2'b10;
    end
    INTERRUPT: begin
      $display("state_n INTERRUPT");
      SC <= 2'b11;
      state_n = FETCH;
    end
    default: begin

      state_n = FETCH;
    end
    endcase
  assign {I, N} = (state == EXECUTE) ? ram_q : ram_q_;

  wire [3:0] P_n = ((I == 4'hD)) ? N : P;
  wire [3:0] X_n = ((I == 4'hE)) ? N : X;
  wire Q_n = (({I, N} == 8'h7a) | ({I, N} == 8'h7b)) ? N[0] : Q;

  reg [5:0] action;
  assign {Ra, ram_rd, ram_wr} = action;

  localparam MEM___  = 2'b00;
  localparam MEM_RD  = 2'b10;
  localparam MEM_WR  = 2'b01;

  always @(state, I, N)
    case (state)
    FETCH, BRANCH2, SKIP:           {action, Rwd} = {P, MEM_RD, Rrd + 16'd1};
    EXECUTE, EXECUTE2:
      casez ({I, N})
       8'h0?:             {action, Rwd} = {N, MEM_RD, Rrd};
       8'h1?:             {action, Rwd} = {N, MEM___, Rrd + 16'd1};
       8'h2?:             {action, Rwd} = {N, MEM___, Rrd - 16'd1};
       8'h4?:             {action, Rwd} = {N, MEM_RD, Rrd + 16'd1};
       8'h5?:             {action, Rwd} = {N, MEM_WR, Rrd};
       8'hd?,
       8'he?,
       8'h8?,
       8'h9?:             {action, Rwd} = {N, MEM___, Rrd};
       8'ha?:             {action, Rwd} = {N, MEM___, Rrd[15:8], D};
       8'hb?:             {action, Rwd} = {N, MEM___, D, Rrd[7:0]};

       8'h73:             {action, Rwd} = {X, MEM_WR, Rrd - 16'd1};
       8'h72,
       {4'h6, 4'b0???}:   {action, Rwd} = {X, MEM_RD, Rrd + 16'd1};
       {4'h6, 4'b1???}:   {action, Rwd} = {X, MEM_WR, Rrd};

      8'h7c, 8'h7d, 8'h7f, 8'hf8, 8'hf9, 8'hfa, 8'hfb, 8'hfc, 8'hfd, 8'hff,
      8'h3?, 8'hc?:                 {action, Rwd} = {P, MEM_RD, Rrd + 16'd1};

      default:                      {action, Rwd} = {X, MEM_RD, Rrd};
      endcase
    BRANCH3:                        {action, Rwd} = {P, MEM___, (I == 4'hc) ? B : Rrd[15:8], ram_q};
    default:                        {action, Rwd} = {X, MEM___, Rrd};
    endcase

  wire [8:0] carry = (I[3]) ? 9'd0 : {8'd0, DF};
  wire [8:0] borrow = (I[3]) ? 9'd0 : ~{9{DF}};
  reg [8:0] DFD_n;
  always @*
    casez ({I, N})
     8'h72,
     8'hf0,
     8'hf8,
     8'h4?,
     8'h0?:               DFD_n = {DF, ram_q};
     8'h8?:               DFD_n = {DF, Rrd[7:0]};
     8'h9?:               DFD_n = {DF, Rrd[15:8]};
     8'b0110_1???:        DFD_n = {DF, io_din};
     8'b1111_?001:        DFD_n = {DF, D | ram_q};
     8'b1111_?010:        DFD_n = {DF, D & ram_q};
     8'b1111_?011:        DFD_n = {DF, D ^ ram_q};
     8'b?111_?100:        DFD_n = {1'b0, D} + {1'b0, ram_q} + carry;
     8'b?111_?101:        DFD_n = ({1'b1, ram_q} - {1'b0, D}) + borrow;
     8'b?111_?111:        DFD_n = ({1'b1, D} - {1'b0, ram_q}) + borrow;
     8'b?111_0110:        DFD_n = {D[0], carry[0], D[7:1]};
     8'b?111_1110:        DFD_n = {D, carry[0]};
    default:                        DFD_n = {DF, D};
    endcase

  assign io_n = N[2:0];
  assign io_out = (I == 4'h6) & ~N[3] & (state == EXECUTE2) & (N[2:0] != 3'b000);
  assign io_inp = (I == 4'h6) & N[3] & (state == EXECUTE) & (N[2:0] != 3'b000);
  assign io_dout = ram_q;
  assign unsupported = {I, N} == 8'h70;

  always @(negedge CLEAR_N or posedge CLOCK) begin

    if (!CLEAR_N) begin
        {ram_q_, Q, P, X} <= 0;
        {DF, D} <= 9'd0;
        R[0] <= 16'd0;
        state <= RESET;
      end
    else begin
      if(!WAIT_N && CLEAR_N) begin
        state <= state_n;
        if (state == EXECUTE)
          {ram_q_, Q, P, X} <= {ram_q, Q_n, P_n, X_n};
        if (state != EXECUTE2)
          R[Ra] <= Rwd;
        if (((state == EXECUTE) & !ram_rd) || (state == EXECUTE2))
          {DF, D} <= DFD_n;
        if (state == BRANCH2)
          B <= ram_q;
        if (state == INTERRUPT) begin

          T[7:4] <= X;
          T[3:0] <= P;

          IE <= 0;
          $display("Interrupt");

        end
        else if(state == DMA_IN) begin
          $display("DMA_IN");

        end
        else if(state == DMA_OUT) begin
          $display("DMA_OUT");

        end
      end

      else if(!CLEAR_N && !WAIT_N) begin
        $display("Load");
      end

      else if(CLEAR_N && WAIT_N) begin
        $display("Run");
      end
    end
  end

endmodule
