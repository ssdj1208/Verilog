`timescale 1ns / 1ps

// RISC-V 执行单元中的组合 ALU。
// 除 RV32I 基本算术/逻辑和移位操作外，还提供 RV32M 运算选择编码；
// 乘除法本身由上层迭代单元完成或通过对应控制信号接入。
module alu(
    input wire[31:0] a,
    input wire[31:0] b,
    input wire[4:0] op,
    output reg[31:0] y
    );

    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_SLL  = 4'd2;
    localparam ALU_SLT  = 4'd3;
    localparam ALU_SLTU = 4'd4;
    localparam ALU_XOR  = 4'd5;
    localparam ALU_SRL  = 4'd6;
    localparam ALU_SRA  = 4'd7;
    localparam ALU_OR   = 4'd8;
    localparam ALU_AND  = 4'd9;
    localparam ALU_COPYB = 5'd10;
    localparam ALU_MUL   = 5'd11;
    localparam ALU_MULH  = 5'd12;
    localparam ALU_MULHSU = 5'd13;
    localparam ALU_MULHU = 5'd14;
    localparam ALU_DIV   = 5'd15;
    localparam ALU_DIVU  = 5'd16;
    localparam ALU_REM   = 5'd17;
    localparam ALU_REMU  = 5'd18;

    // ALU 不含内部状态，所有结果均由当前操作码和两个输入组合产生。
    always @(*) begin
        case (op)
            ALU_ADD:   y = a + b;
            ALU_SUB:   y = a - b;
            ALU_SLL:   y = a << b[4:0];
            ALU_SLT:   y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU:  y = (a < b) ? 32'd1 : 32'd0;
            ALU_XOR:   y = a ^ b;
            ALU_SRL:   y = a >> b[4:0];
            ALU_SRA:   y = $signed(a) >>> b[4:0];
            ALU_OR:    y = a | b;
            ALU_AND:   y = a & b;
            ALU_COPYB: y = b;
            ALU_MUL,
            ALU_MULH,
            ALU_MULHSU,
            ALU_MULHU,
            ALU_DIV,
            ALU_DIVU,
            ALU_REM,
            ALU_REMU: y = 32'b0;
            default:   y = 32'b0;
        endcase
    end
endmodule
