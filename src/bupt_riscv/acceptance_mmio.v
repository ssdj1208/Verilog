`timescale 1ns / 1ps

// 自动验收 MMIO 外设。
// 软件通过固定地址写入控制、状态、失败位和显示槽位，硬件保存结果并提供读回。
module acceptance_mmio(
    input wire clk,
    input wire rst,
    input wire we,
    input wire re,
    input wire[7:0] addr,
    input wire[31:0] wdata,
    input wire[3:0] display_sel_i,
    output reg[31:0] rdata,
    output wire active_o,
    output wire[15:0] status_o,
    output wire[15:0] fail_o,
    output wire[31:0] live_result_o,
    output wire[31:0] display_value_o,
    output wire[7:0] display_dp_o
    );

    reg[31:0] control_r;
    reg[15:0] status_r;
    reg[15:0] fail_r;
    reg[31:0] live_result_r;
    reg[31:0] display_value_r[0:15];
    reg[7:0] display_dp_r[0:15];

    wire value_slot = (addr[7:6] == 2'b01) && (addr[1:0] == 2'b00);
    wire dp_slot = (addr[7:6] == 2'b10) && (addr[1:0] == 2'b00);
    wire[3:0] slot_index = addr[5:2];

    integer slot;
    // 写寄存器在时钟沿提交；复位清除上一轮验收内容。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            control_r <= 32'b0;
            status_r <= 16'b0;
            fail_r <= 16'b0;
            live_result_r <= 32'b0;
            for (slot = 0; slot < 16; slot = slot + 1) begin
                display_value_r[slot] <= 32'b0;
                display_dp_r[slot] <= 8'b0;
            end
        end else if (we) begin
            if (addr == 8'h00) begin
                control_r <= wdata;
            end else if (addr == 8'h04) begin
                status_r <= wdata[15:0];
            end else if (addr == 8'h08) begin
                live_result_r <= wdata;
            end else if (addr == 8'h0c) begin
                fail_r <= wdata[15:0];
            end else if (value_slot) begin
                display_value_r[slot_index] <= wdata;
            end else if (dp_slot) begin
                display_dp_r[slot_index] <= wdata[7:0];
            end
        end
    end

    // 组合读回逻辑，根据地址选择控制、状态或显示槽位数据。
    always @(*) begin
        if (addr == 8'h00) begin
            rdata = control_r;
        end else if (addr == 8'h04) begin
            rdata = {16'b0, status_r};
        end else if (addr == 8'h08) begin
            rdata = live_result_r;
        end else if (addr == 8'h0c) begin
            rdata = {16'b0, fail_r};
        end else if (value_slot) begin
            rdata = display_value_r[slot_index];
        end else if (dp_slot) begin
            rdata = {24'b0, display_dp_r[slot_index]};
        end else begin
            rdata = 32'b0;
        end
    end

    assign active_o = control_r[0];
    assign status_o = status_r;
    assign fail_o = fail_r;
    assign live_result_o = live_result_r;
    assign display_value_o = display_value_r[display_sel_i];
    assign display_dp_o = display_dp_r[display_sel_i];

endmodule
