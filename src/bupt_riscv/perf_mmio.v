`timescale 1ns / 1ps

module perf_mmio(
    input wire clk,
    input wire rst,
    input wire we,
    input wire re,
    input wire[4:0] addr,
    input wire[31:0] wdata,
    output reg[31:0] rdata,
    input wire retire,
    input wire branch,
    input wire mispredict,
    input wire stall
    );

    reg[31:0] cycles;
    reg[31:0] retired;
    reg[31:0] branches;
    reg[31:0] mispredicts;
    reg[31:0] stalls;

    always @(posedge clk) begin
        if (rst || (we && addr == 5'h1c && wdata[0])) begin
            cycles <= 32'b0;
            retired <= 32'b0;
            branches <= 32'b0;
            mispredicts <= 32'b0;
            stalls <= 32'b0;
        end else begin
            cycles <= cycles + 32'd1;
            if (retire) retired <= retired + 32'd1;
            if (branch) branches <= branches + 32'd1;
            if (mispredict) mispredicts <= mispredicts + 32'd1;
            if (stall) stalls <= stalls + 32'd1;
        end
    end

    always @(*) begin
        case (addr)
            5'h00: rdata = cycles;
            5'h04: rdata = retired;
            5'h08: rdata = branches;
            5'h0c: rdata = mispredicts;
            5'h10: rdata = stalls;
            default: rdata = 32'b0;
        endcase
    end
endmodule
