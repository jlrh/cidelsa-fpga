`default_nettype none

module coin_debounce #(
    parameter [15:0] DEGLITCH_CYCLES = 16'd28132,
    parameter [21:0] PULSE_CYCLES    = 22'd1406619
)(
    input  wire clk,
    input  wire raw,
    output reg  clean
);

    reg [15:0] deb_cnt = 16'd0;
    reg        deb_in_r = 1'b0;
    reg        deb = 1'b0;
    always @(posedge clk) begin
        deb_in_r <= raw;
        if (raw != deb_in_r) deb_cnt <= 16'd0;
        else if (deb_cnt < DEGLITCH_CYCLES) deb_cnt <= deb_cnt + 16'd1;
        if (deb_cnt == DEGLITCH_CYCLES) deb <= deb_in_r;
    end

    reg        deb_r = 1'b0;
    reg [21:0] pulse_cnt = 22'd0;
    initial clean = 1'b0;
    always @(posedge clk) begin
        deb_r <= deb;
        if (!clean && deb && !deb_r) begin
            clean     <= 1'b1;
            pulse_cnt <= PULSE_CYCLES;
        end else if (clean) begin
            if (pulse_cnt == 22'd0) clean <= 1'b0;
            else                    pulse_cnt <= pulse_cnt - 22'd1;
        end
    end
endmodule

`default_nettype wire
