`timescale 1ns / 1ps

// 迭代除法/取余单元。
// 使用逐位试商算法实现 RV32M 的 DIV、DIVU、REM 和 REMU，结果需要多个时钟周期。
// 模块同时处理除数为零及有符号最小值除以 -1 等规范规定的特殊情况。
module iter_div(
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed_op,
    input wire rem_op,
    input wire[31:0] dividend_i,
    input wire[31:0] divisor_i,
    output reg busy,
    output reg ready,
    output reg[31:0] result
    );

    reg[31:0] dividend;
    reg[31:0] divisor;
    reg[31:0] quotient;
    reg[31:0] remainder;
    reg[5:0] count;
    reg quotient_neg;
    reg remainder_neg;
    reg result_is_rem;

    wire dividend_neg = signed_op & dividend_i[31];
    wire divisor_neg = signed_op & divisor_i[31];
    wire[31:0] dividend_abs = dividend_neg ? (~dividend_i + 32'd1) : dividend_i;
    wire[31:0] divisor_abs = divisor_neg ? (~divisor_i + 32'd1) : divisor_i;

    wire[32:0] rem_shift = {remainder, dividend[31]};
    wire rem_ge_div = rem_shift >= {1'b0, divisor};
    wire[32:0] rem_sub = rem_shift - {1'b0, divisor};
    wire[31:0] quotient_next = {quotient[30:0], rem_ge_div};
    wire[31:0] remainder_next = rem_ge_div ? rem_sub[31:0] : rem_shift[31:0];
    wire[31:0] quotient_signed = quotient_neg ? (~quotient_next + 32'd1) : quotient_next;
    wire[31:0] remainder_signed = remainder_neg ? (~remainder_next + 32'd1) : remainder_next;

    // busy 期间每拍推进一次商/余数计算，完成后锁存结果并拉高 done 一拍。
    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            ready <= 1'b0;
            result <= 32'b0;
            dividend <= 32'b0;
            divisor <= 32'b0;
            quotient <= 32'b0;
            remainder <= 32'b0;
            count <= 6'b0;
            quotient_neg <= 1'b0;
            remainder_neg <= 1'b0;
            result_is_rem <= 1'b0;
        end else begin
            ready <= 1'b0;

            if (start && !busy) begin
                result_is_rem <= rem_op;
                if (divisor_i == 32'b0) begin
                    result <= rem_op ? dividend_i : 32'hffff_ffff;
                    ready <= 1'b1;
                    busy <= 1'b0;
                end else if (signed_op && (dividend_i == 32'h8000_0000) &&
                             (divisor_i == 32'hffff_ffff)) begin
                    result <= rem_op ? 32'b0 : 32'h8000_0000;
                    ready <= 1'b1;
                    busy <= 1'b0;
                end else begin
                    busy <= 1'b1;
                    dividend <= dividend_abs;
                    divisor <= divisor_abs;
                    quotient <= 32'b0;
                    remainder <= 32'b0;
                    count <= 6'b0;
                    quotient_neg <= dividend_neg ^ divisor_neg;
                    remainder_neg <= dividend_neg;
                end
            end else if (busy) begin
                dividend <= {dividend[30:0], 1'b0};
                quotient <= quotient_next;
                remainder <= remainder_next;

                if (count == 6'd31) begin
                    busy <= 1'b0;
                    ready <= 1'b1;
                    result <= result_is_rem ? remainder_signed : quotient_signed;
                end else begin
                    count <= count + 6'd1;
                end
            end
        end
    end
endmodule
