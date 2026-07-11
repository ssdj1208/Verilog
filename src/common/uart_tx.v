`timescale 1ns / 1ps

// UART 发送器，采用 8 位数据、1 个起始位、1 个停止位、无奇偶校验格式。
// tx_start 在空闲时接受一个字节，tx_busy 表示当前帧尚未发送完成。
module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input wire clk,
    input wire rst,
    input wire tx_start,
    input wire[7:0] tx_data,
    output reg tx,
    output reg tx_busy
    );

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg[1:0] state;
    reg[31:0] clk_count;
    reg[2:0] bit_index;
    reg[7:0] data;

    // 状态机依次发送起始位、8 个数据位和停止位，每个位持续 CLKS_PER_BIT 个时钟。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            clk_count <= 32'b0;
            bit_index <= 3'b0;
            data <= 8'b0;
            tx <= 1'b1;
            tx_busy <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_count <= 32'b0;
                    bit_index <= 3'b0;
                    if (tx_start) begin
                        data <= tx_data;
                        tx <= 1'b0;
                        tx_busy <= 1'b1;
                        state <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0;
                    tx_busy <= 1'b1;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 32'b0;
                        bit_index <= 3'b0;
                        tx <= data[0];
                        state <= S_DATA;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                S_DATA: begin
                    tx_busy <= 1'b1;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 32'b0;
                        if (bit_index == 3'd7) begin
                            tx <= 1'b1;
                            state <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            tx <= data[bit_index + 1'b1];
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b1;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 32'b0;
                        tx_busy <= 1'b0;
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
