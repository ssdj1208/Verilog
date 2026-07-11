`timescale 1ns / 1ps

// 片上 Block RAM 包装器。
// 支持按字节写使能，读端保持简单的同步读接口，供总线中的片上 RAM 使用。
module bram_ram #(
    parameter ADDR_WIDTH = 10
)(
    input wire clk,
    input wire we,
    input wire[3:0] wstrb,
    input wire[ADDR_WIDTH-1:0] word_addr,
    input wire[31:0] wdata,
    output reg[31:0] rdata
    );

    reg [31:0] ram[0:(1 << ADDR_WIDTH)-1];

    // 每个写选通位对应一个字节；未选通的字节保持原值。
    always @(posedge clk) begin
        if (we) begin
            if (wstrb[0]) ram[word_addr][7:0]   <= wdata[7:0];
            if (wstrb[1]) ram[word_addr][15:8]  <= wdata[15:8];
            if (wstrb[2]) ram[word_addr][23:16] <= wdata[23:16];
            if (wstrb[3]) ram[word_addr][31:24] <= wdata[31:24];
        end
        rdata <= ram[word_addr];
    end
endmodule
