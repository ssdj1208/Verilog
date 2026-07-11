`timescale 1ns / 1ps
// 带异步复位和同步清零的寄存器。
// clear 通常用于分支、异常或冒险处理时向流水线注入气泡。
module floprc #(parameter WIDTH = 8)(
	input wire clk,rst,clear,
	input wire[WIDTH-1:0] d,
	output reg[WIDTH-1:0] q
    );

	// rst 优先级最高；正常工作时 clear 优先于普通数据装载。
	always @(posedge clk,posedge rst) begin
		if(rst) begin
			q <= 0;
		end else if (clear)begin
			q <= 0;
		end else begin
			q <= d;
		end
	end
endmodule
