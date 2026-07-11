`timescale 1ns / 1ps
// 带异步复位的普通寄存器。
// rst 有效时立即清零，否则每个时钟沿采样输入 d。
module flopr #(parameter WIDTH = 8)(
	input wire clk,rst,
	input wire[WIDTH-1:0] d,
	output reg[WIDTH-1:0] q
    );
	// 异步复位用于快速清除流水线和控制状态。
	always @(posedge clk,posedge rst) begin
		if(rst) begin
			q <= 0;
		end else begin
			q <= d;
		end
	end
endmodule
