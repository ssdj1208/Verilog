`timescale 1ns / 1ps

module iter_mul(
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed_a,
    input wire signed_b,
    input wire high_word,
    input wire[31:0] a_i,
    input wire[31:0] b_i,
    output reg busy,
    output reg ready,
    output reg[31:0] result
    );

    reg[63:0] acc;
    reg[63:0] multiplicand;
    reg[31:0] multiplier;
    reg[5:0] count;
    reg result_neg;
    reg result_high;

    wire a_neg = signed_a & a_i[31];
    wire b_neg = signed_b & b_i[31];
    wire[31:0] a_abs = a_neg ? (~a_i + 32'd1) : a_i;
    wire[31:0] b_abs = b_neg ? (~b_i + 32'd1) : b_i;

    wire[63:0] acc_next = multiplier[0] ? (acc + multiplicand) : acc;
    wire[63:0] product_signed = result_neg ? (~acc_next + 64'd1) : acc_next;

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            ready <= 1'b0;
            result <= 32'b0;
            acc <= 64'b0;
            multiplicand <= 64'b0;
            multiplier <= 32'b0;
            count <= 6'b0;
            result_neg <= 1'b0;
            result_high <= 1'b0;
        end else begin
            ready <= 1'b0;

            if (start && !busy) begin
                busy <= 1'b1;
                acc <= 64'b0;
                multiplicand <= {32'b0, a_abs};
                multiplier <= b_abs;
                count <= 6'b0;
                result_neg <= a_neg ^ b_neg;
                result_high <= high_word;
            end else if (busy) begin
                acc <= acc_next;
                multiplicand <= multiplicand << 1;
                multiplier <= multiplier >> 1;

                if (count == 6'd31) begin
                    busy <= 1'b0;
                    ready <= 1'b1;
                    result <= result_high ? product_signed[63:32] : product_signed[31:0];
                end else begin
                    count <= count + 6'd1;
                end
            end
        end
    end
endmodule
