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
  input               CLOCK,      // CLOCK
  input               CLEAR_N,    // CLEAR_N   (RESET)

  output reg          Q,          // external pin Q 
  input      [3:0]    EF,         // external flags EF1 to EF4, separate pins negative

  // WAIT CLEAR  Control Lines
  // Clear 0 Wait 0 Load
  // Clear 0 Wait 1 Reset
  // Clear 1 Wait 0 Pause
  // Clear 1 Wait 1 Run

  // SC_1   State Code Line
  // SC_0   State Code Line
  // SC1 0 SC0 0  S0 Fetch
  // SC1 0 SC0 1  S1 Execute
  // SC1 1 SC0 0  S2 DMA
  // SC1 1 SC0 1  S3 Interrupt

  // MRD_N  Read Level
  // DATABUS 0-7  BUS0-BUS7
  // N0     I/O Line
  // N1     I/O Line
  // N2     I/O Line
  // XTAL_N
  // DMA_IN_N
  // DMA_OUT_N
  // MWR_N  Write Pulse
  // TPA    Timing Pulse
  // TPB    Timing Pulse
  // MEMORY_ADDR 0-7 MA0-MA7  Memory Address Lines

  input               WAIT_N,      // WAIT_N
  input               INT_N,       // INT_N
  input               dma_in_req,  // DMA_IN_N
  input               dma_out_req, // DMA_OUT_N
  output reg [1:0]    SC,          // SC1 SC0

  input      [7:0]    io_din,     // IO data in
  output     [7:0]    io_dout,    // IO data out
  output     [2:0]    io_n,       // IO control lines: N2,N1,N0
  output  wire        io_inp,     // IO input signal
  output  wire        io_out,     // IO output signal

  output              unsupported,// unsupported instruction signal

  output              ram_rd,     // RAM read enable      // MRD_N
  output              ram_wr,     // RAM write enable     // MWR_N
  output     [15:0]   ram_a,      // RAM address
  input      [7:0]    ram_q,      // RAM read data
  output     [7:0]    ram_d      // RAM write data

  //output  wire         TPA,        // Timing Pulse  (RAM)
  //output  wire         TPB         // Timing Pulse  (IO)
);

  // ---------- control signals -------------------------- 
  //reg   waiting;
  //assign waiting = (wait_req && resetq) ? 1'b1 : 1'b0;  
  reg   IE;   // Interrupt Enable

  // ---------- execution states -------------------------
  reg [3:0] state, state_n = 4'd0;

  localparam RESET     = 4'd0;    //    hardware reset asserted
  localparam FETCH     = 4'd1;    // S0 fetching opcode from PC
  localparam EXECUTE   = 4'd2;    // S1 main exection state
  localparam EXECUTE2  = 4'd3;    // S1 second execute, if memory was read
  localparam BRANCH2   = 4'd4;    //    long branch, collect new PC hi-byte
  localparam BRANCH3   = 4'd5;    //    short branch, new PC lo-byte
  localparam SKIP      = 4'd6;    //    for untaken

  localparam DMA_IN    = 4'd7;    // S2 DMA_IN state
  localparam DMA_OUT   = 4'd8;    // S2 DMA_OUT state
  localparam INTERRUPT = 4'd9;    // S3 Interrupt state

/*
  localparam RESET [3:0]     = 4'b0000;  // sc_execute
  localparam RESET2 [3:0]    = 4'b0001;  // sc_execute
  localparam LOAD [3:0]      = 4'b0010;  // sc_execute
  localparam FETCH [3:0]     = 4'b0011;  // sc_fetch
  localparam EXECUTE [3:0]   = 4'b0100;  // sc_execute
  localparam EXECUTE2 [3:0]  = 4'b0101;  // sc_execute
  localparam DMA_IN [3:0]    = 4'b0110;  // sc_dma
  localparam DMA_OUT [3:0]   = 4'b0111;  // sc_dma
  localparam INTERRUPT [3:0] = 4'b1000;  // sc_interrupt
*/ 

  // ---------- registers --------------------------------
  reg   [3:0] P;                  // Program Counter
  reg   [3:0] X;                  // Data Pointer
  reg   [7:0] T;                  // Temporary Register

  reg  [15:0] R[0:15];            // 16x16 register file
  wire  [3:0] Ra;                 // which register to work on this clock
  wire [15:0] Rrd = R[Ra];        // read out the selected register
  reg  [15:0] Rwd;                // write-back value for the register

  reg   [7:0] D;                  // data register (accumulator)
  reg         DF;                 // data flag (ALU carry)
  reg   [7:0] B;                  // used for hi-byte of long branch
  reg   [7:0] ram_q_;             // registered copy of ram_q, for multi-cycle ops
  wire  [3:0] I, N;               // the current instruction

  // ---------- RAM hookups ------------------------------
  assign ram_d = (I == 4'h6) ? io_din : D;
  assign ram_a = Rrd;             // RAM address always one of the 16-bit regs

/*
  // TPA TPB
  // TPA occurs every 8 cycles, TPA precedes TPB
  reg [7:0] TP_counter = 0;
  wire TPA_ = 0;
  wire TPB_ = 1;
  assign TPA = TPA_;
  assign TPB = TPB_;
  always @(posedge CLOCK) begin
    if(TP_counter == 7) begin
      TPA_ <= ~TPA_;
      TPB_ <= ~TPB_;
      TP_counter <= 0;
    end
    else
      TP_counter <= TP_counter + 1;
  end
*/

  // ---------- conditional branch -----------------------
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

  // ---------- fetch/interrupt/dma/execute ----------------------------
  always @*
    case (state)
    FETCH: begin
      SC <= 2'b00; // SC1 0 SC0 0  S0 Fetch
      //$display("state_n FETCH");
      state_n = EXECUTE;
    end
    EXECUTE: begin
      SC <= 2'b01; // SC1 0 SC0 1  S1 Execute
      /* 
      if (dma_in_req == 1'b1)
        state_n <= DMA_IN;
      else if (dma_out_req == 1'b1)
        state_n <= DMA_OUT;
      else if (INT_N == 1'b1 & IE == 1'b1)
        state_n <= INTERRUPT;
      else begin
      */
        case (I)
          4'h3:     state_n = take ? BRANCH3 : FETCH;
          4'hc:     state_n = take ? BRANCH2 : SKIP;
          default:  state_n = ram_rd ? EXECUTE2 : FETCH;
        endcase
      //end
      /*
      if (ir == inst_idl)
        state_n <= EXECUTE;
      else
        state_n <= FETCH;
      */
    end
    BRANCH2: begin
      $display("state_n BRANCH2");
      state_n = BRANCH3;
    end
    DMA_IN: begin
      $display("state_n DMA_IN");
      SC <= 2'b10; // SC1 1 SC0 0  S2 DMA      
    end
    DMA_OUT: begin
      $display("state_n DMA_OUT");
      SC <= 2'b10; // SC1 1 SC0 0  S2 DMA      
    end    
    INTERRUPT: begin
      $display("state_n INTERRUPT");
      SC <= 2'b11; // SC1 1 SC0 1  S3 Interrupt        
      state_n = FETCH;
    end
    default: begin
      //$display("state_n default");
      state_n = FETCH;
    end
    endcase
  assign {I, N} = (state == EXECUTE) ? ram_q : ram_q_;

  // ---------- decode and execute -----------------------
  wire [3:0] P_n = ((I == 4'hD)) ? N : P;           // SEP
  wire [3:0] X_n = ((I == 4'hE)) ? N : X;           // SEX
  wire Q_n = (({I, N} == 8'h7a) | ({I, N} == 8'h7b)) ? N[0] : Q; // REQ, SEQ

  reg [5:0] action;                 // reg. address; RAM rd; RAM wr
  assign {Ra, ram_rd, ram_wr} = action;

  localparam MEM___  = 2'b00;       // no memory access
  localparam MEM_RD  = 2'b10;       // memory read strobe
  localparam MEM_WR  = 2'b01;       // memory write strobe

  always @(state, I, N)
    case (state)
    FETCH, BRANCH2, SKIP:           {action, Rwd} = {P, MEM_RD, Rrd + 16'd1};
    EXECUTE, EXECUTE2:
      casez ({I, N})
      /* LDN  */ 8'h0?:             {action, Rwd} = {N, MEM_RD, Rrd};
      /* INC  */ 8'h1?:             {action, Rwd} = {N, MEM___, Rrd + 16'd1};
      /* DEC  */ 8'h2?:             {action, Rwd} = {N, MEM___, Rrd - 16'd1};
      /* LDA  */ 8'h4?:             {action, Rwd} = {N, MEM_RD, Rrd + 16'd1};
      /* STR  */ 8'h5?:             {action, Rwd} = {N, MEM_WR, Rrd};
      /* SEP  */ 8'hd?,
      /* SEX  */ 8'he?,
      /* GLO  */ 8'h8?,
      /* GHI  */ 8'h9?:             {action, Rwd} = {N, MEM___, Rrd};
      /* PLO  */ 8'ha?:             {action, Rwd} = {N, MEM___, Rrd[15:8], D};
      /* PHI  */ 8'hb?:             {action, Rwd} = {N, MEM___, D, Rrd[7:0]};

      /* STXD */ 8'h73:             {action, Rwd} = {X, MEM_WR, Rrd - 16'd1};
      /* LDXA */ 8'h72,
      /* OUT  */ {4'h6, 4'b0???}:   {action, Rwd} = {X, MEM_RD, Rrd + 16'd1};
      /* INP  */ {4'h6, 4'b1???}:   {action, Rwd} = {X, MEM_WR, Rrd};

      /* immediate and branch instructions must fetch from R[P] */
      8'h7c, 8'h7d, 8'h7f, 8'hf8, 8'hf9, 8'hfa, 8'hfb, 8'hfc, 8'hfd, 8'hff,
      8'h3?, 8'hc?:                 {action, Rwd} = {P, MEM_RD, Rrd + 16'd1};

      default:                      {action, Rwd} = {X, MEM_RD, Rrd};
      endcase
    BRANCH3:                        {action, Rwd} = {P, MEM___, (I == 4'hc) ? B : Rrd[15:8], ram_q};
    default:                        {action, Rwd} = {X, MEM___, Rrd};
    endcase

  wire [8:0] carry = (I[3]) ? 9'd0 : {8'd0, DF};      // 0 or 1 for ADC
  wire [8:0] borrow = (I[3]) ? 9'd0 : ~{9{DF}};       // -1 or 0 for SDB and SMB
  reg [8:0] DFD_n;
  always @*
    casez ({I, N})
    /* LDXA */ 8'h72,
    /* LDX  */ 8'hf0,
    /* LDI  */ 8'hf8,
    /* LDA  */ 8'h4?,
    /* LDN  */ 8'h0?:               DFD_n = {DF, ram_q};
    /* GLO  */ 8'h8?:               DFD_n = {DF, Rrd[7:0]};
    /* GHI  */ 8'h9?:               DFD_n = {DF, Rrd[15:8]};
    /* INP  */ 8'b0110_1???:        DFD_n = {DF, io_din};
    /* OR   */ 8'b1111_?001:        DFD_n = {DF, D | ram_q};
    /* AND  */ 8'b1111_?010:        DFD_n = {DF, D & ram_q};
    /* XOR  */ 8'b1111_?011:        DFD_n = {DF, D ^ ram_q};
    /* ADD  */ 8'b?111_?100:        DFD_n = {1'b0, D} + {1'b0, ram_q} + carry;
    /* SD   */ 8'b?111_?101:        DFD_n = ({1'b1, ram_q} - {1'b0, D}) + borrow;
    /* SM   */ 8'b?111_?111:        DFD_n = ({1'b1, D} - {1'b0, ram_q}) + borrow;
    /* SHR  */ 8'b?111_0110:        DFD_n = {D[0], carry[0], D[7:1]};
    /* SHL  */ 8'b?111_1110:        DFD_n = {D, carry[0]};
    default:                        DFD_n = {DF, D};
    endcase

  assign io_n = N[2:0];
  assign io_out = (I == 4'h6) & ~N[3] & (state == EXECUTE2) & (N[2:0] != 3'b000);
  assign io_inp = (I == 4'h6) & N[3] & (state == EXECUTE) & (N[2:0] != 3'b000);
  assign io_dout = ram_q;
  assign unsupported = {I, N} == 8'h70;
  /*
  always @(posedge CLOCK) begin
    if(unsupported) begin
      $display("Unsupported instruction: %h", {I, N});
    end
  end
  */
  // ---------- cycle commit -----------------------------
  always @(negedge CLEAR_N or posedge CLOCK) begin
    // CLEAR WAIT Control Lines
    // Clear 0 Wait 0 Load
    // Clear 0 Wait 1 Reset
    // Clear 1 Wait 0 Pause
    // Clear 1 Wait 1 Run
    // Reset
    /*
    if (cpuMode_ != RUN)
    {
        if (p_Video != NULL)
            p_Video->reset();
    }
    */
    if (!CLEAR_N) begin  // WAIT_N ??   if (clear_ == 0 && wait_==1)
        {ram_q_, Q, P, X} <= 0;
        {DF, D} <= 9'd0;
        R[0] <= 16'd0;
        state <= RESET;
      end 
    else begin
      if(!WAIT_N && CLEAR_N) begin  // Pause  if (clear_ == 1 && wait_==0) cpuMode_ = PAUSE;
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
          /*
            registerT_= (dataPointer_<<4) | programCounter_;
            dataPointer_=2;
            programCounter_=1;
            interruptEnable_=0;          
          */
          T[7:4] <= X;
          T[3:0] <= P;
          //X <= 2;
          //P <= 1;          
          IE <= 0;
          $display("Interrupt");
            /*
            begin
               SC <= sc_interrupt;
               if (dma_in_req == 1'b1)
                  next_state <= DMA_IN;
               else if (dma_out_req == 1'b1)
                  next_state <= DMA_OUT;
               else
                  next_state <= FETCH;
               load_t <= 1'b1;
               xp_sel <= xp_sel_interrupt;
               ie_sel <= ie_sel_0;
            end
            */
        end
        else if(state == DMA_IN) begin
          $display("DMA_IN");
            /*
            begin
               SC <= sc_dma;
               r_addr_sel <= r_addr_sel_0;
               adder_opb_sel <= adder_opb_sel_1;
               r_write_data_sel <= r_write_data_sel_adder;
               r_write_high <= 1'b1;
               r_write_low <= 1'b1;
               mem_write <= 1'b1;
               if (dma_in_req == 1'b1)
                  next_state <= DMA_IN;
               else if (dma_out_req == 1'b1)
                  next_state <= DMA_OUT;
               else if (clear == 1'b1)
               begin
                  r_write_high <= 1'b0;
                  r_write_low <= 1'b0;
                  next_state <= state_load;
               end
               else if (INT_N == 1'b1 & IE == 1'b1)
                  next_state <= INTERRUPT;
               else
                  next_state <= FETCH;
            end
            */
        end
        else if(state == DMA_OUT) begin
          $display("DMA_OUT");
            /*
            begin
               SC <= sc_dma;
               r_addr_sel <= r_addr_sel_0;
               adder_opb_sel <= adder_opb_sel_1;
               r_write_data_sel <= r_write_data_sel_adder;
               r_write_high <= 1'b1;
               r_write_low <= 1'b1;
               mem_read <= 1'b1;
               if (dma_in_req == 1'b1)
                  next_state <= DMA_IN;
               else if (dma_out_req == 1'b1)
                  next_state <= DMA_OUT;
               else if (clear == 1'b1)
               begin
                  r_write_high <= 1'b0;
                  r_write_low <= 1'b0;
                  next_state <= state_load;
               end
               else if (int_req == 1'b1 & ie == 1'b1)
                  next_state <= INTERRUPT;
               else
                  next_state <= FETCH;
            end
            */
        end
      end
      // Clear 0 Wait 0 Load      if (clear_ == 0 && wait_==0) cpuMode_ = LOAD;
      else if(!CLEAR_N && !WAIT_N) begin
        $display("Load");
      end
      // Clear 1 Wait 1 Run  if (clear_ == 1 && wait_==1) cpuMode_ = RUN;
      else if(CLEAR_N && WAIT_N) begin
        $display("Run");
      end
    end
  end

endmodule
