`timescale 1ns / 1ps
// 程序计数器寄存器。
// en=1 时在时钟沿装入 d；en=0 时保持当前地址，用于取指等待和流水线暂停。
module pc #(parameter WIDTH = 8)(
	input wire clk,rst,en,
	input wire[WIDTH-1:0] d,
	output reg[WIDTH-1:0] q
    );
	// 复位后从零地址开始执行启动代码。
	always @(posedge clk,posedge rst) begin
		if(rst) begin
			q <= 0;
		end else if(en) begin
			q <= d;
		end
	end
endmodule
