`timescale 1ns / 1ps

module dcache_2way_lru(
    input wire clk,
    input wire rst,

    input wire cpu_valid,
    input wire cpu_we,
    input wire[3:0] cpu_wstrb,
    input wire[31:0] cpu_addr,
    input wire[31:0] cpu_wdata,
    output wire cpu_ready,
    output wire[31:0] cpu_rdata,

    output reg mem_valid,
    output reg mem_we,
    output reg[3:0] mem_wstrb,
    output reg[31:0] mem_addr,
    output reg[31:0] mem_wdata,
    input wire mem_ready,
    input wire[31:0] mem_rdata,

    input wire clear_stats,
    output reg[31:0] access_count,
    output reg[31:0] hit_count,
    output reg[31:0] miss_count,
    output reg[31:0] replacement_count,
    output reg[31:0] refill_cycle_count
    );

    localparam SETS = 16;
    localparam LINE_WORDS = 4;

    localparam S_IDLE = 3'd0;
    localparam S_WRITE_WAIT = 3'd1;
    localparam S_REFILL_ISSUE = 3'd2;
    localparam S_REFILL_WAIT = 3'd3;
    localparam S_DONE = 3'd4;

    reg valid0[0:SETS-1];
    reg valid1[0:SETS-1];
    reg[23:0] tag0[0:SETS-1];
    reg[23:0] tag1[0:SETS-1];
    reg[31:0] data0[0:SETS-1][0:LINE_WORDS-1];
    reg[31:0] data1[0:SETS-1][0:LINE_WORDS-1];
    reg lru[0:SETS-1]; // 0 replaces way0, 1 replaces way1

    reg[2:0] state;
    reg ready_r;
    reg[31:0] rdata_r;

    reg pending_victim;
    reg[3:0] pending_index;
    reg[23:0] pending_tag;
    reg[1:0] pending_word;
    reg[31:0] pending_line_base;
    reg[1:0] refill_word;
    reg[31:0] refill_buf[0:LINE_WORDS-1];

    wire[3:0] index = cpu_addr[7:4];
    wire[1:0] word = cpu_addr[3:2];
    wire[23:0] tag = cpu_addr[31:8];
    wire[31:0] line_base = {cpu_addr[31:4], 4'b0000};
    wire hit0 = valid0[index] && (tag0[index] == tag);
    wire hit1 = valid1[index] && (tag1[index] == tag);
    wire hit = hit0 | hit1;
    wire victim = !valid0[index] ? 1'b0 :
                  !valid1[index] ? 1'b1 : lru[index];

    assign cpu_ready = ready_r;
    assign cpu_rdata = rdata_r;

    function [31:0] merge_word;
        input [31:0] old_word;
        input [31:0] new_word;
        input [3:0] strb;
        begin
            merge_word[7:0] = strb[0] ? new_word[7:0] : old_word[7:0];
            merge_word[15:8] = strb[1] ? new_word[15:8] : old_word[15:8];
            merge_word[23:16] = strb[2] ? new_word[23:16] : old_word[23:16];
            merge_word[31:24] = strb[3] ? new_word[31:24] : old_word[31:24];
        end
    endfunction

    integer i;
    integer w;
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            ready_r <= 1'b0;
            rdata_r <= 32'b0;
            mem_valid <= 1'b0;
            mem_we <= 1'b0;
            mem_wstrb <= 4'b0;
            mem_addr <= 32'b0;
            mem_wdata <= 32'b0;
            pending_victim <= 1'b0;
            pending_index <= 4'b0;
            pending_tag <= 24'b0;
            pending_word <= 2'b0;
            pending_line_base <= 32'b0;
            refill_word <= 2'b0;
            access_count <= 32'b0;
            hit_count <= 32'b0;
            miss_count <= 32'b0;
            replacement_count <= 32'b0;
            refill_cycle_count <= 32'b0;
            for (i = 0; i < SETS; i = i + 1) begin
                valid0[i] <= 1'b0;
                valid1[i] <= 1'b0;
                tag0[i] <= 24'b0;
                tag1[i] <= 24'b0;
                lru[i] <= 1'b0;
                for (w = 0; w < LINE_WORDS; w = w + 1) begin
                    data0[i][w] <= 32'b0;
                    data1[i][w] <= 32'b0;
                end
            end
        end else begin
            ready_r <= 1'b0;
            mem_valid <= 1'b0;

            if (clear_stats) begin
                access_count <= 32'b0;
                hit_count <= 32'b0;
                miss_count <= 32'b0;
                replacement_count <= 32'b0;
                refill_cycle_count <= 32'b0;
                for (i = 0; i < SETS; i = i + 1) begin
                    valid0[i] <= 1'b0;
                    valid1[i] <= 1'b0;
                    lru[i] <= 1'b0;
                end
            end

            case (state)
                S_IDLE: begin
                    if (cpu_valid) begin
                        access_count <= clear_stats ? 32'd1 : access_count + 32'd1;
                        if (cpu_we) begin
                            if (hit0) begin
                                data0[index][word] <= merge_word(data0[index][word], cpu_wdata, cpu_wstrb);
                                lru[index] <= 1'b1;
                                hit_count <= clear_stats ? 32'd1 : hit_count + 32'd1;
                            end else if (hit1) begin
                                data1[index][word] <= merge_word(data1[index][word], cpu_wdata, cpu_wstrb);
                                lru[index] <= 1'b0;
                                hit_count <= clear_stats ? 32'd1 : hit_count + 32'd1;
                            end else begin
                                miss_count <= clear_stats ? 32'd1 : miss_count + 32'd1;
                            end

                            mem_valid <= 1'b1;
                            mem_we <= 1'b1;
                            mem_wstrb <= cpu_wstrb;
                            mem_addr <= cpu_addr;
                            mem_wdata <= cpu_wdata;
                            state <= S_WRITE_WAIT;
                        end else if (hit) begin
                            rdata_r <= hit0 ? data0[index][word] : data1[index][word];
                            ready_r <= 1'b1;
                            hit_count <= clear_stats ? 32'd1 : hit_count + 32'd1;
                            lru[index] <= hit0 ? 1'b1 : 1'b0;
                            state <= S_DONE;
                        end else begin
                            miss_count <= clear_stats ? 32'd1 : miss_count + 32'd1;
                            if (valid0[index] && valid1[index]) begin
                                replacement_count <= clear_stats ? 32'd1 : replacement_count + 32'd1;
                            end
                            pending_victim <= victim;
                            pending_index <= index;
                            pending_tag <= tag;
                            pending_word <= word;
                            pending_line_base <= line_base;
                            refill_word <= 2'b0;
                            state <= S_REFILL_ISSUE;
                        end
                    end
                end

                S_WRITE_WAIT: begin
                    if (!mem_ready) begin
                        mem_valid <= 1'b1;
                    end
                    if (mem_ready) begin
                        ready_r <= 1'b1;
                        state <= S_DONE;
                    end
                end

                S_REFILL_ISSUE: begin
                    mem_valid <= 1'b1;
                    mem_we <= 1'b0;
                    mem_wstrb <= 4'b0000;
                    mem_addr <= pending_line_base + {28'b0, refill_word, 2'b00};
                    mem_wdata <= 32'b0;
                    state <= S_REFILL_WAIT;
                end

                S_REFILL_WAIT: begin
                    refill_cycle_count <= clear_stats ? 32'd1 : refill_cycle_count + 32'd1;
                    if (!mem_ready) begin
                        mem_valid <= 1'b1;
                    end
                    if (mem_ready) begin
                        refill_buf[refill_word] <= mem_rdata;
                        if (refill_word == (LINE_WORDS-1)) begin
                            if (pending_victim == 1'b0) begin
                                valid0[pending_index] <= 1'b1;
                                tag0[pending_index] <= pending_tag;
                                for (w = 0; w < LINE_WORDS; w = w + 1) begin
                                    data0[pending_index][w] <= (w == refill_word) ? mem_rdata : refill_buf[w];
                                end
                                lru[pending_index] <= 1'b1;
                            end else begin
                                valid1[pending_index] <= 1'b1;
                                tag1[pending_index] <= pending_tag;
                                for (w = 0; w < LINE_WORDS; w = w + 1) begin
                                    data1[pending_index][w] <= (w == refill_word) ? mem_rdata : refill_buf[w];
                                end
                                lru[pending_index] <= 1'b0;
                            end
                            rdata_r <= (pending_word == refill_word) ? mem_rdata : refill_buf[pending_word];
                            ready_r <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            refill_word <= refill_word + 2'd1;
                            state <= S_REFILL_ISSUE;
                        end
                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
