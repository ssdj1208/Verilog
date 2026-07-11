`timescale 1ns / 1ps
// 带使能和同步复位的寄存器。
// en=0 时保持原值；rst 在时钟沿被采样并将输出清零。
module flopenr #(parameter WIDTH = 8)(
	input wire clk,rst,en,
	input wire[WIDTH-1:0] d,
	output reg[WIDTH-1:0] q
    );
	// 常用于允许暂停的流水线级间寄存器。
	always @(posedge clk) begin
		if(rst) begin
			q <= 0;
		end else if(en) begin
			q <= d;
		end
	end
endmodule
