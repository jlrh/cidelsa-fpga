`timescale 1ns/1ps
`default_nettype none

module vis_regs (
    input  wire        clk,
    input  wire        reset,

    input  wire        reg_wr,
    input  wire [2:0]  reg_n,
    input  wire [7:0]  cpu_data,
    input  wire [15:0] cpu_addr,

    output reg  [2:0]  bkg,
    output reg         cfc,
    output reg         dispoff,
    output reg  [1:0]  col,
    output reg         freshorz,

    output reg  [3:0]  toneamp,
    output reg  [2:0]  tonefreq,
    output reg         toneoff,
    output reg  [6:0]  tonediv,

    output reg         cmem,
    output reg         line9,
    output reg         line16,
    output reg         dblpage,
    output reg         fresvert,
    output reg  [3:0]  wnamp,
    output reg  [2:0]  wnfreq,
    output reg         wnoff,

    output reg  [10:0] pma,
    output reg  [10:0] hma
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
            3'd3: begin
                bkg      <= cpu_data[2:0];
                cfc      <= cpu_data[3];
                dispoff  <= cpu_data[4];
                col      <= cpu_data[6:5];
                freshorz <= cpu_data[7];
            end
            3'd4: begin
                toneamp  <= cpu_addr[3:0];
                tonefreq <= cpu_addr[6:4];
                toneoff  <= cpu_addr[7];
                tonediv  <= cpu_addr[14:8];
            end
            3'd5: begin
                cmem     <= cpu_addr[0];
                line9    <= cpu_addr[3];
                line16   <= cpu_addr[5];
                dblpage  <= cpu_addr[6];
                fresvert <= cpu_addr[7];
                wnamp    <= cpu_addr[11:8];
                wnfreq   <= cpu_addr[14:12];
                wnoff    <= cpu_addr[15];

                pma      <= cpu_addr[0] ? cpu_addr[10:0] : 11'd0;
            end
            3'd6: begin
                pma      <= cpu_addr[10:0];
            end
            3'd7: begin
                hma      <= {cpu_addr[10:2], 2'b00};
            end
            default: ;
            endcase
        end
    end

endmodule

`default_nettype wire
