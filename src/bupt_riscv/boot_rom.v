`timescale 1ns / 1ps

// 启动 ROM：为取指端或数据端提供同步读取的只读存储器。
// 地址输入使用字地址，实际内容通常由 Vivado 初始化文件加载。
module boot_rom(
    input wire clk,
    input wire[11:0] a,
    output reg[31:0] spo
    );

    reg [31:0] rom[0:4095];

    initial begin
        $readmemh("bupt_riscv_boot.mem", rom);
    end

    // 同步读：在时钟沿采样地址，并在寄存器中保存对应指令/数据。
    always @(posedge clk) begin
        spo <= rom[a];
    end
endmodule
