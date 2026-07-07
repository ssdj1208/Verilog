`timescale 1ns / 1ps

module fp_mmio(
    input wire clk,
    input wire rst,
    input wire we,
    input wire re,
    input wire[4:0] addr,
    input wire[31:0] wdata,
    output reg[31:0] rdata
    );

    reg[31:0] op_a;
    reg[31:0] op_b;
    reg[1:0] op_sel; // 0 add, 1 mul
    wire[31:0] add_result;
    wire[31:0] mul_result;
    wire[31:0] result = (op_sel == 2'd1) ? mul_result : add_result;

    fp32_add_pos add_unit(op_a, op_b, add_result);
    fp32_mul_pos mul_unit(op_a, op_b, mul_result);

    always @(posedge clk) begin
        if (rst) begin
            op_a <= 32'b0;
            op_b <= 32'b0;
            op_sel <= 2'b0;
        end else if (we) begin
            case (addr)
                5'h00: op_a <= wdata;
                5'h04: op_b <= wdata;
                5'h08: op_sel <= wdata[1:0];
                default: begin end
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            rdata <= 32'b0;
        end else if (re) begin
            case (addr)
                5'h00: rdata <= op_a;
                5'h04: rdata <= op_b;
                5'h08: rdata <= {30'b0, op_sel};
                5'h0c: rdata <= result;
                5'h10: rdata <= 32'd1; // ready
                default: rdata <= 32'b0;
            endcase
        end
    end
endmodule

module fp32_add_pos(
    input wire[31:0] a,
    input wire[31:0] b,
    output reg[31:0] y
    );

    reg[7:0] exp_big;
    reg[23:0] mant_big;
    reg[23:0] mant_small;
    reg[7:0] shift;
    reg[24:0] sum;
    reg[7:0] exp_y;
    reg[22:0] frac_y;

    always @(*) begin
        if (a[30:0] == 31'b0) begin
            y = b;
        end else if (b[30:0] == 31'b0) begin
            y = a;
        end else begin
            if (a[30:23] >= b[30:23]) begin
                exp_big = a[30:23];
                mant_big = {1'b1, a[22:0]};
                mant_small = {1'b1, b[22:0]};
                shift = a[30:23] - b[30:23];
            end else begin
                exp_big = b[30:23];
                mant_big = {1'b1, b[22:0]};
                mant_small = {1'b1, a[22:0]};
                shift = b[30:23] - a[30:23];
            end

            if (shift > 8'd24) mant_small = 24'b0;
            else mant_small = mant_small >> shift;

            sum = {1'b0, mant_big} + {1'b0, mant_small};
            if (sum[24]) begin
                exp_y = exp_big + 8'd1;
                frac_y = sum[23:1];
            end else begin
                exp_y = exp_big;
                frac_y = sum[22:0];
            end
            y = {1'b0, exp_y, frac_y};
        end
    end
endmodule

module fp32_mul_pos(
    input wire[31:0] a,
    input wire[31:0] b,
    output reg[31:0] y
    );

    reg[47:0] product;
    reg[8:0] exp_sum;
    reg[7:0] exp_y;
    reg[22:0] frac_y;

    always @(*) begin
        if (a[30:0] == 31'b0 || b[30:0] == 31'b0) begin
            y = 32'b0;
        end else begin
            product = {1'b1, a[22:0]} * {1'b1, b[22:0]};
            exp_sum = {1'b0, a[30:23]} + {1'b0, b[30:23]} - 9'd127;
            if (product[47]) begin
                exp_y = exp_sum[7:0] + 8'd1;
                frac_y = product[46:24];
            end else begin
                exp_y = exp_sum[7:0];
                frac_y = product[45:23];
            end
            y = {1'b0, exp_y, frac_y};
        end
    end
endmodule
