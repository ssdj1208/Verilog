`timescale 1ns / 1ps

module hex_display(
    input wire clk,
    input wire rst,
    input wire enable_i,
    input wire[31:0] value_i,
    input wire[7:0] dp_mask_i,
    output reg[7:0] an_o,
    output reg[6:0] seg_o,
    output reg dp_o
    );

    reg[15:0] scan_div_r;
    wire[2:0] scan_idx = scan_div_r[15:13];
    reg[3:0] digit;

    function [6:0] hex_to_seg;
        input [3:0] value;
        begin
            case (value)
                4'h0: hex_to_seg = 7'b1000000;
                4'h1: hex_to_seg = 7'b1111001;
                4'h2: hex_to_seg = 7'b0100100;
                4'h3: hex_to_seg = 7'b0110000;
                4'h4: hex_to_seg = 7'b0011001;
                4'h5: hex_to_seg = 7'b0010010;
                4'h6: hex_to_seg = 7'b0000010;
                4'h7: hex_to_seg = 7'b1111000;
                4'h8: hex_to_seg = 7'b0000000;
                4'h9: hex_to_seg = 7'b0010000;
                4'hA: hex_to_seg = 7'b0001000;
                4'hB: hex_to_seg = 7'b0000011;
                4'hC: hex_to_seg = 7'b1000110;
                4'hD: hex_to_seg = 7'b0100001;
                4'hE: hex_to_seg = 7'b0000110;
                default: hex_to_seg = 7'b0001110;
            endcase
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            scan_div_r <= 16'b0;
        end else begin
            scan_div_r <= scan_div_r + 16'd1;
        end
    end

    always @(*) begin
        case (scan_idx)
            3'd0: an_o = 8'b11111110;
            3'd1: an_o = 8'b11111101;
            3'd2: an_o = 8'b11111011;
            3'd3: an_o = 8'b11110111;
            3'd4: an_o = 8'b11101111;
            3'd5: an_o = 8'b11011111;
            3'd6: an_o = 8'b10111111;
            default: an_o = 8'b01111111;
        endcase
        digit = (value_i >> (scan_idx * 4)) & 4'hf;
        seg_o = hex_to_seg(digit);
        dp_o = ~dp_mask_i[scan_idx];
        if (!enable_i) begin
            an_o = 8'hff;
            seg_o = 7'h7f;
            dp_o = 1'b1;
        end
    end

endmodule
