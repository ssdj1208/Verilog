`timescale 1ns / 1ps

module demo_clock_ctrl #(
    parameter integer SLOW_DIV = 25000000,
    parameter integer FAST_DIV = 5000000,
    parameter integer STARTUP_PULSES = 14
)(
    input wire clk_i,
    input wire rst_i,
    input wire demo_mode_i,
    input wire run_toggle_i,
    input wire step_i,
    input wire speed_toggle_i,
    output wire soc_clk_o,
    output reg run_active_o,
    output reg speed_sel_o
    );

    reg [24:0] pace_count_r;
    reg [7:0] startup_pulses_r;
    reg demo_ce_r;
    wire demo_clk;

    wire [24:0] pace_limit = speed_sel_o ? (FAST_DIV - 1) : (SLOW_DIV - 1);
    wire startup_active = demo_mode_i && (startup_pulses_r != 8'd0);
    wire pace_hit = (pace_count_r == pace_limit);
    wire run_tick = demo_mode_i && run_active_o && pace_hit;
    wire demo_pulse_req = startup_active || step_i || run_tick;

    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            run_active_o <= 1'b0;
            speed_sel_o <= 1'b0;
            pace_count_r <= 25'd0;
            startup_pulses_r <= STARTUP_PULSES[7:0];
            demo_ce_r <= 1'b0;
        end else begin
            demo_ce_r <= demo_mode_i && demo_pulse_req;

            if (run_toggle_i) begin
                run_active_o <= ~run_active_o;
            end
            if (speed_toggle_i) begin
                speed_sel_o <= ~speed_sel_o;
            end

            if (!demo_mode_i || !run_active_o) begin
                pace_count_r <= 25'd0;
            end else if (pace_hit) begin
                pace_count_r <= 25'd0;
            end else begin
                pace_count_r <= pace_count_r + 25'd1;
            end

            if (startup_active) begin
                startup_pulses_r <= startup_pulses_r - 8'd1;
            end
        end
    end

`ifdef SYNTHESIS
    BUFGCE demo_clk_bufg(
        .I(clk_i),
        .CE(demo_ce_r),
        .O(demo_clk)
        );
`else
    assign demo_clk = clk_i & demo_ce_r;
`endif

    assign soc_clk_o = demo_mode_i ? demo_clk : clk_i;
endmodule
