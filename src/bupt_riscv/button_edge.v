`timescale 1ns / 1ps

module button_edge #(
    parameter integer CTR_WIDTH = 19
)(
    input wire clk,
    input wire rst,
    input wire raw_i,
    output reg level_o,
    output wire pressed_o
    );

    reg [1:0] sync_r;
    reg [CTR_WIDTH-1:0] stable_count_r;
    reg prev_level_r;

    wire sync_level = sync_r[1];
    wire stable_done = &stable_count_r;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync_r <= 2'b00;
            stable_count_r <= {CTR_WIDTH{1'b0}};
            level_o <= 1'b0;
            prev_level_r <= 1'b0;
        end else begin
            sync_r <= {sync_r[0], raw_i};
            prev_level_r <= level_o;

            if (sync_level == level_o) begin
                stable_count_r <= {CTR_WIDTH{1'b0}};
            end else begin
                stable_count_r <= stable_count_r + {{CTR_WIDTH-1{1'b0}}, 1'b1};
                if (stable_done) begin
                    level_o <= sync_level;
                    stable_count_r <= {CTR_WIDTH{1'b0}};
                end
            end
        end
    end

    assign pressed_o = level_o & ~prev_level_r;
endmodule
