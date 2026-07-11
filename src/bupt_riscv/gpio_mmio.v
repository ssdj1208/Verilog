`timescale 1ns / 1ps

// GPIO MMIO 外设。
// 当前实现提供一个简单的 32 位写寄存器，并将低 16 位映射到板载 LED。
module gpio_mmio(
    input wire clk,
    input wire rst,
    input wire we,
    input wire[31:0] wdata,
    output wire[31:0] rdata,
    output wire[15:0] led
    );

    reg [31:0] gpio_out;

    // 写操作在 clk 上升沿提交；复位时关闭全部 LED。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            gpio_out <= 32'b0;
        end else if (we) begin
            gpio_out <= wdata;
        end
    end

    assign led = gpio_out[15:0];
    assign rdata = gpio_out;
endmodule
