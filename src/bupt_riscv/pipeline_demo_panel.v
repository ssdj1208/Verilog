`timescale 1ns / 1ps

module pipeline_demo_panel(
    input wire clk,
    input wire rst,
    input wire demo_mode_i,
    input wire page_toggle_i,
    input wire[2:0] stage_sel_i,
    input wire run_active_i,
    input wire speed_sel_i,
    input wire[31:0] pcF_i,
    input wire[31:0] pcD_i,
    input wire[31:0] pcE_i,
    input wire[31:0] pcM_i,
    input wire[31:0] pcW_i,
    input wire validF_i,
    input wire validD_i,
    input wire validE_i,
    input wire validM_i,
    input wire validW_i,
    input wire stall_loaduse_i,
    input wire stall_muldiv_i,
    input wire stall_ifetch_i,
    input wire stall_dcache_i,
    input wire flush_branch_i,
    input wire flush_trap_i,
    output reg[15:0] led_o,
    output reg[7:0] an_o,
    output reg[6:0] seg_o,
    output reg dp_o,
    output reg page_o
    );

    reg [15:0] scan_div_r;
    wire [2:0] scan_idx = scan_div_r[15:13];

    wire [31:0] detail_pc =
        (stage_sel_i == 3'd1) ? pcD_i :
        (stage_sel_i == 3'd2) ? pcE_i :
        (stage_sel_i == 3'd3) ? pcM_i :
        (stage_sel_i == 3'd4) ? pcW_i : pcF_i;

    wire [3:0] stall_digit = {stall_dcache_i, stall_ifetch_i, stall_muldiv_i, stall_loaduse_i};
    wire [3:0] flush_digit = {2'b00, flush_trap_i, flush_branch_i};
    wire [3:0] mode_digit =
        run_active_i ? (speed_sel_i ? 4'hA : 4'h2) :
        (speed_sel_i ? 4'h1 : 4'h0);

    reg [3:0] hex_digit;
    reg dp_en;

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
            page_o <= 1'b0;
            scan_div_r <= 16'b0;
        end else begin
            scan_div_r <= scan_div_r + 16'd1;
            if (page_toggle_i) begin
                page_o <= ~page_o;
            end
        end
    end

    always @(*) begin
        led_o = 16'b0;
        led_o[0] = validF_i;
        led_o[1] = validD_i;
        led_o[2] = validE_i;
        led_o[3] = validM_i;
        led_o[4] = validW_i;
        led_o[5] = stall_loaduse_i;
        led_o[6] = stall_muldiv_i;
        led_o[7] = stall_ifetch_i;
        led_o[8] = stall_dcache_i;
        led_o[9] = flush_branch_i;
        led_o[10] = flush_trap_i;
        led_o[11] = ~run_active_i;
        led_o[12] = run_active_i;
        led_o[13] = page_o;
        led_o[14] = speed_sel_i;
        led_o[15] = demo_mode_i;
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

        if (!page_o) begin
            case (scan_idx)
                3'd0: begin hex_digit = mode_digit;   dp_en = 1'b0; end
                3'd1: begin hex_digit = flush_digit;  dp_en = 1'b0; end
                3'd2: begin hex_digit = stall_digit;  dp_en = 1'b0; end
                3'd3: begin hex_digit = pcW_i[5:2];   dp_en = validW_i; end
                3'd4: begin hex_digit = pcM_i[5:2];   dp_en = validM_i; end
                3'd5: begin hex_digit = pcE_i[5:2];   dp_en = validE_i; end
                3'd6: begin hex_digit = pcD_i[5:2];   dp_en = validD_i; end
                default: begin hex_digit = pcF_i[5:2]; dp_en = validF_i; end
            endcase
        end else begin
            case (scan_idx)
                3'd0: begin hex_digit = detail_pc[3:0];   dp_en = 1'b0; end
                3'd1: begin hex_digit = detail_pc[7:4];   dp_en = 1'b0; end
                3'd2: begin hex_digit = detail_pc[11:8];  dp_en = 1'b0; end
                3'd3: begin hex_digit = detail_pc[15:12]; dp_en = 1'b0; end
                3'd4: begin hex_digit = detail_pc[19:16]; dp_en = 1'b0; end
                3'd5: begin hex_digit = detail_pc[23:20]; dp_en = 1'b0; end
                3'd6: begin hex_digit = detail_pc[27:24]; dp_en = 1'b0; end
                default: begin hex_digit = detail_pc[31:28]; dp_en = 1'b0; end
            endcase
        end

        seg_o = hex_to_seg(hex_digit);
        dp_o = ~dp_en;
    end
endmodule
