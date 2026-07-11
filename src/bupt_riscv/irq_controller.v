`timescale 1ns / 1ps

// 中断控制器。
// 将定时器、UART 等外设的事件状态汇总为 CPU 可见的 IRQ 线，
// 并通过 MMIO 提供 pending/enable 等控制信息。
module irq_controller(
    input wire clk,
    input wire rst,
    input wire we,
    input wire re,
    input wire[3:0] wstrb,
    input wire[3:0] addr,
    input wire[31:0] wdata,
    output reg[31:0] rdata,
    input wire timer_irq,
    output wire[7:0] irq_lines
    );

    reg[7:0] irq_enable;
    wire[7:0] irq_pending = {7'b0, timer_irq};

    assign irq_lines = irq_pending & irq_enable;

    // pending 状态在时钟域内锁存，写入清除请求具有优先级。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            irq_enable <= 8'b0000_0001;
        end else if (we && |wstrb) begin
            case (addr[3:2])
                2'b01: irq_enable <= wdata[7:0];
                default: ;
            endcase
        end
    end

    // 组合读取逻辑：按 MMIO 地址返回状态寄存器内容。
    always @(*) begin
        case (addr[3:2])
            2'b00: rdata = {24'b0, irq_pending};
            2'b01: rdata = {24'b0, irq_enable};
            2'b10: rdata = {24'b0, irq_lines};
            default: rdata = 32'b0;
        endcase
    end
endmodule
