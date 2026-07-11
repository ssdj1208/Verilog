`timescale 1ns / 1ps

// UART 接收器，采用 8 位数据、1 个起始位、1 个停止位、无奇偶校验格式。
// 检测起始位后按位中心采样，完整接收后在 rx_valid 上输出一个时钟周期的脉冲。
module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input wire clk,
    input wire rst,
    input wire rx,
    output reg[7:0] rx_data,
    output reg rx_valid
    );

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg[1:0] state;
    reg[31:0] clk_count;
    reg[2:0] bit_index;
    reg[7:0] data;

    reg rx_meta;
    reg rx_sync;

    // 两级同步器将异步串行输入安全地带入本地 clk 时钟域。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    // 接收状态机：确认起始位、采样数据位并检查停止位。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            clk_count <= 32'b0;
            bit_index <= 3'b0;
            data <= 8'b0;
            rx_data <= 8'b0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    clk_count <= 32'b0;
                    bit_index <= 3'b0;
                    if (rx_sync == 1'b0) begin
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (clk_count == (CLKS_PER_BIT / 2)) begin
                        if (rx_sync == 1'b0) begin
                            clk_count <= 32'b0;
                            state <= S_DATA;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                S_DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 32'b0;
                        data[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                S_STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 32'b0;
                        rx_data <= data;
                        rx_valid <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
