`timescale 1ns / 1ps
// 带使能、同步复位和同步清零的寄存器。
// clear 用于分支/异常冲刷，en 用于暂停时保持流水线状态。
module flopenrc #(parameter WIDTH = 8)(
	input wire clk,rst,en,clear,
	input wire[WIDTH-1:0] d,
	output reg[WIDTH-1:0] q
    );
	// 清零优先于使能；没有清零且未使能时保持当前值。
	always @(posedge clk) begin
		if(rst) begin
			q <= 0;
		end else if(clear) begin
			q <= 0;
		end else if(en) begin
			q <= d;
		end
	end
endmodule
