`timescale 1ns / 1ps

// 流水线演示时钟/运行控制器。
// 根据启动脉冲、运行状态和速度选择产生演示用的单步或连续运行节拍。
// 该模块只负责控制节拍，不参与 CPU 数据通路和指令执行。
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
    wire soc_ce_req = ~demo_mode_i | demo_ce_r;
`ifndef SYNTHESIS
    reg soc_gate_r;
`endif

    wire [24:0] pace_limit = speed_sel_o ? (FAST_DIV - 1) : (SLOW_DIV - 1);
    wire startup_active = demo_mode_i && (startup_pulses_r != 8'd0);
    wire pace_hit = (pace_count_r == pace_limit);
    wire run_tick = demo_mode_i && run_active_o && pace_hit;
    wire demo_pulse_req = startup_active || step_i || run_tick;

    // 主时钟域：保存运行模式、启动阶段计数和节拍分频状态。
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
    BUFGCE soc_clk_bufg(
        .I(clk_i),
        .CE(soc_ce_req),
        .O(soc_clk_o)
        );
`else
    // 下降沿域：生成跨到主时钟逻辑前的窄脉冲，避免同一上升沿重复触发。
    always @(negedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            soc_gate_r <= 1'b0;
        end else begin
            soc_gate_r <= soc_ce_req;
        end
    end

    assign soc_clk_o = clk_i & soc_gate_r;
`endif
endmodule
