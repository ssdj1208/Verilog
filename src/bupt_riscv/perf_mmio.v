`timescale 1ns / 1ps

// 性能计数器 MMIO 外设。
// 累计周期、退休指令、分支、预测失败、各类暂停/冲刷和前递事件，
// 软件可通过写 clear 位清零整组计数器。
module perf_mmio(
    input wire clk,
    input wire rst,
    input wire we,
    input wire re,
    input wire[5:0] addr,
    input wire[31:0] wdata,
    output reg[31:0] rdata,
    input wire retire,
    input wire branch,
    input wire mispredict,
    input wire stall,
    input wire stall_loaduse,
    input wire stall_muldiv,
    input wire stall_dcache,
    input wire stall_ifetch,
    input wire stall_ddr_wait,
    input wire flush_branch,
    input wire flush_trap,
    input wire forward_event
    );

    reg[31:0] cycles;
    reg[31:0] retired;
    reg[31:0] branches;
    reg[31:0] mispredicts;
    reg[31:0] stalls;
    reg[31:0] stalls_loaduse;
    reg[31:0] stalls_muldiv;
    reg[31:0] stalls_dcache;
    reg[31:0] stalls_ifetch;
    reg[31:0] stalls_ddr_wait;
    reg[31:0] flushes_branch;
    reg[31:0] flushes_trap;
    reg[31:0] forwards;

    wire clear = rst || (we && addr == 6'h1c && wdata[0]);

    // 每个事件输入为单周期脉冲时，对应计数器递增一次。
    always @(posedge clk) begin
        if (clear) begin
            cycles <= 32'b0;
            retired <= 32'b0;
            branches <= 32'b0;
            mispredicts <= 32'b0;
            stalls <= 32'b0;
            stalls_loaduse <= 32'b0;
            stalls_muldiv <= 32'b0;
            stalls_dcache <= 32'b0;
            stalls_ifetch <= 32'b0;
            stalls_ddr_wait <= 32'b0;
            flushes_branch <= 32'b0;
            flushes_trap <= 32'b0;
            forwards <= 32'b0;
        end else begin
            cycles <= cycles + 32'd1;
            if (retire) retired <= retired + 32'd1;
            if (branch) branches <= branches + 32'd1;
            if (mispredict) mispredicts <= mispredicts + 32'd1;
            if (stall) stalls <= stalls + 32'd1;
            if (stall_loaduse) stalls_loaduse <= stalls_loaduse + 32'd1;
            if (stall_muldiv) stalls_muldiv <= stalls_muldiv + 32'd1;
            if (stall_dcache) stalls_dcache <= stalls_dcache + 32'd1;
            if (stall_ifetch) stalls_ifetch <= stalls_ifetch + 32'd1;
            if (stall_ddr_wait) stalls_ddr_wait <= stalls_ddr_wait + 32'd1;
            if (flush_branch) flushes_branch <= flushes_branch + 32'd1;
            if (flush_trap) flushes_trap <= flushes_trap + 32'd1;
            if (forward_event) forwards <= forwards + 32'd1;
        end
    end

    // 根据 MMIO 偏移选择要返回的统计值。
    always @(*) begin
        case (addr)
            6'h00: rdata = cycles;
            6'h04: rdata = retired;
            6'h08: rdata = branches;
            6'h0c: rdata = mispredicts;
            6'h10: rdata = stalls;
            6'h14: rdata = stalls_loaduse;
            6'h18: rdata = stalls_muldiv;
            6'h1c: rdata = stalls_dcache;
            6'h20: rdata = stalls_ifetch;
            6'h24: rdata = stalls_ddr_wait;
            6'h28: rdata = flushes_branch;
            6'h2c: rdata = flushes_trap;
            6'h30: rdata = forwards;
            default: rdata = 32'b0;
        endcase
    end
endmodule
