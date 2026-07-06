`timescale 1ns / 1ps

module load_ext(
    input wire[31:0] rdata,
    input wire[1:0] addr,
    input wire[2:0] funct3,
    output reg[31:0] y
    );

    reg[7:0] byte_val;
    reg[15:0] half_val;

    always @(*) begin
        case (addr)
            2'b00: byte_val = rdata[7:0];
            2'b01: byte_val = rdata[15:8];
            2'b10: byte_val = rdata[23:16];
            default: byte_val = rdata[31:24];
        endcase

        half_val = addr[1] ? rdata[31:16] : rdata[15:0];

        case (funct3)
            3'b000: y = {{24{byte_val[7]}}, byte_val}; // lb
            3'b001: y = {{16{half_val[15]}}, half_val}; // lh
            3'b010: y = rdata; // lw
            3'b100: y = {24'b0, byte_val}; // lbu
            3'b101: y = {16'b0, half_val}; // lhu
            default: y = rdata;
        endcase
    end
endmodule
