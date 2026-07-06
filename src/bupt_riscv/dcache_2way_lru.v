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
    output reg[31:0] replacement_count
    );

    localparam SETS = 16;
    localparam S_IDLE = 2'd0;
    localparam S_WAIT = 2'd1;
    localparam S_DONE = 2'd2;

    reg valid0[0:SETS-1];
    reg valid1[0:SETS-1];
    reg[25:0] tag0[0:SETS-1];
    reg[25:0] tag1[0:SETS-1];
    reg[31:0] data0[0:SETS-1];
    reg[31:0] data1[0:SETS-1];
    reg lru[0:SETS-1]; // 0 replaces way0, 1 replaces way1

    reg[1:0] state;
    reg ready_r;
    reg[31:0] rdata_r;
    reg pending_read;
    reg pending_victim;
    reg[3:0] pending_index;
    reg[25:0] pending_tag;

    wire[3:0] index = cpu_addr[5:2];
    wire[25:0] tag = cpu_addr[31:6];
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
            pending_read <= 1'b0;
            pending_victim <= 1'b0;
            pending_index <= 4'b0;
            pending_tag <= 26'b0;
            access_count <= 32'b0;
            hit_count <= 32'b0;
            miss_count <= 32'b0;
            replacement_count <= 32'b0;
            for (i = 0; i < SETS; i = i + 1) begin
                valid0[i] <= 1'b0;
                valid1[i] <= 1'b0;
                tag0[i] <= 26'b0;
                tag1[i] <= 26'b0;
                data0[i] <= 32'b0;
                data1[i] <= 32'b0;
                lru[i] <= 1'b0;
            end
        end else begin
            ready_r <= 1'b0;
            mem_valid <= 1'b0;

            if (clear_stats) begin
                access_count <= 32'b0;
                hit_count <= 32'b0;
                miss_count <= 32'b0;
                replacement_count <= 32'b0;
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
                                data0[index] <= merge_word(data0[index], cpu_wdata, cpu_wstrb);
                                lru[index] <= 1'b1;
                                hit_count <= clear_stats ? 32'd1 : hit_count + 32'd1;
                            end else if (hit1) begin
                                data1[index] <= merge_word(data1[index], cpu_wdata, cpu_wstrb);
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
                            pending_read <= 1'b0;
                            state <= S_WAIT;
                        end else if (hit) begin
                            rdata_r <= hit0 ? data0[index] : data1[index];
                            ready_r <= 1'b1;
                            hit_count <= clear_stats ? 32'd1 : hit_count + 32'd1;
                            lru[index] <= hit0 ? 1'b1 : 1'b0;
                            state <= S_DONE;
                        end else begin
                            miss_count <= clear_stats ? 32'd1 : miss_count + 32'd1;
                            if (valid0[index] && valid1[index]) begin
                                replacement_count <= clear_stats ? 32'd1 : replacement_count + 32'd1;
                            end
                            mem_valid <= 1'b1;
                            mem_we <= 1'b0;
                            mem_wstrb <= 4'b0000;
                            mem_addr <= cpu_addr;
                            mem_wdata <= 32'b0;
                            pending_read <= 1'b1;
                            pending_victim <= victim;
                            pending_index <= index;
                            pending_tag <= tag;
                            state <= S_WAIT;
                        end
                    end
                end

                S_WAIT: begin
                    if (!mem_ready) begin
                        mem_valid <= 1'b1;
                    end
                    if (mem_ready) begin
                        if (pending_read) begin
                            if (pending_victim == 1'b0) begin
                                valid0[pending_index] <= 1'b1;
                                tag0[pending_index] <= pending_tag;
                                data0[pending_index] <= mem_rdata;
                                lru[pending_index] <= 1'b1;
                            end else begin
                                valid1[pending_index] <= 1'b1;
                                tag1[pending_index] <= pending_tag;
                                data1[pending_index] <= mem_rdata;
                                lru[pending_index] <= 1'b0;
                            end
                            rdata_r <= mem_rdata;
                        end
                        ready_r <= 1'b1;
                        state <= S_DONE;
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
