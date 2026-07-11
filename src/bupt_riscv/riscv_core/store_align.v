`timescale 1ns / 1ps

// Store 数据对齐单元。
// 根据 store 类型和地址低两位生成写数据及 4 位字节写选通，
// 使总线能够正确执行 SB、SH 和 SW。
// Store 数据对齐单元。
// 根据地址低两位和 store 宽度生成写数据及 4 位字节写选通，
// 供片上 RAM、MMIO 和 DDR 后端使用。
module store_align(
    input wire[31:0] store_data,
    input wire[1:0] addr,
    input wire[2:0] funct3,
    output reg[31:0] wdata,
    output reg[3:0] wstrb
    );

    // 未选中的字节填零，wstrb 负责告知下游哪些字节真正写入。
    always @(*) begin
        wdata = store_data;
        wstrb = 4'b0000;
        case (funct3)
            3'b000: begin // sb
                wdata = store_data << (addr * 8);
                wstrb = 4'b0001 << addr;
            end
            3'b001: begin // sh
                wdata = addr[1] ? {store_data[15:0], 16'b0} : {16'b0, store_data[15:0]};
                wstrb = addr[1] ? 4'b1100 : 4'b0011;
            end
            3'b010: begin // sw
                wdata = store_data;
                wstrb = 4'b1111;
            end
            default: begin
                wdata = store_data;
                wstrb = 4'b0000;
            end
        endcase
    end
endmodule
