`timescale 1ns / 1ps

// 浮点演示 MMIO 外设。
// 通过 MMIO 接收两个正的单精度浮点操作数和运算选择，保存结果并提供 ready 状态。
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
    reg[31:0] result_reg;
    // busy_count 用于控制启动后的固定处理延迟。
    reg[1:0] busy_count;
    reg busy;
    reg ready;
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
            result_reg <= 32'b0;
            busy_count <= 2'b0;
            busy <= 1'b0;
            ready <= 1'b1;
        end else if (we) begin
            case (addr)
                5'h00: begin
                    op_a <= wdata;
                    ready <= 1'b0;
                end
                5'h04: begin
                    op_b <= wdata;
                    ready <= 1'b0;
                end
                5'h08: begin
                    op_sel <= wdata[1:0];
                    busy <= 1'b1;
                    ready <= 1'b0;
                    busy_count <= 2'd2;
                end
                default: begin end
            endcase
        end else if (busy) begin
            if (busy_count != 2'b0) begin
                busy_count <= busy_count - 2'b01;
            end else begin
                result_reg <= result;
                busy <= 1'b0;
                ready <= 1'b1;
            end
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
                5'h0c: rdata <= result_reg;
                5'h10: rdata <= {31'b0, ready};
                default: rdata <= 32'b0;
            endcase
        end
    end
endmodule

// 正数单精度浮点加法器：指数对齐、尾数相加、规格化并重新编码。
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

    // 组合加法数据通路，不保存跨周期状态。
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

// 正数单精度浮点乘法器：计算尾数乘积和阶码相加后的规格化结果。
module fp32_mul_pos(
    input wire[31:0] a,
    input wire[31:0] b,
    output reg[31:0] y
    );

    reg[47:0] product;
    reg[8:0] exp_sum;
    reg[7:0] exp_y;
    reg[22:0] frac_y;

    // 组合乘法数据通路，不保存跨周期状态。
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
