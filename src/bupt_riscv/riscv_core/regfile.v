`timescale 1ns / 1ps
// RV32I 32×32 通用寄存器堆。
// x0 始终读为 0；写端在下降沿提交，使同一周期的组合读保持稳定。
module regfile(
	input wire clk,
	input wire we3,
	input wire[4:0] ra1,ra2,wa3,
	input wire[31:0] wd3,
	output wire[31:0] rd1,rd2
    );

	reg [31:0] rf[31:0];

	// 只有有效写回且 rd 不为 x0 时才更新寄存器。
	always @(negedge clk) begin
		if(we3 && (wa3 != 5'b0)) begin
			 rf[wa3] <= wd3;
		end
	end

	assign rd1 = (ra1 != 0) ? rf[ra1] : 0;
	assign rd2 = (ra2 != 0) ? rf[ra2] : 0;
endmodule
