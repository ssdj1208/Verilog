`timescale 1ns / 1ps

// Direct-mapped instruction cache.
//   - 64 sets, 4-word lines, 1 KB total.
//   - index = pc[9:4], tag = pc[31:10], word = pc[3:2].
//   - Read-only (no dirty bit). Miss refills a whole line from the backend.
//   - Hit: combinational ready=1, registered rdata (1-cycle latency, same as
//     boot_rom today, so the existing IF/ID timing is unchanged).
//   - Miss: cpu_ready=0 stalls the CPU while the FSM refills the line from
//     the backend (registered boot_rom: 1 beat per cycle). After commit the
//     requested word is returned and ready asserts combinationally.
module icache #(
    parameter LINES = 64,
    parameter LINE_WORDS = 4
)(
    input wire clk,
    input wire rst,
    input wire invalidate,     // flush all entries (e.g. on stats clear)

    // CPU fetch side
    input  wire [31:0] cpu_addr,
    output wire [31:0] cpu_rdata,
    output wire        cpu_ready,

    // Backend (boot_rom) side
    output reg  [31:0] be_addr,
    input  wire [31:0] be_rdata,

    output reg [31:0] access_count,
    output reg [31:0] hit_count,
    output reg [31:0] miss_count,
    output reg [31:0] refill_cycle_count
    );

    localparam IDX_W  = 6;   // log2(64 lines)
    localparam WORD_W = 2;   // log2(4 words/line)
    localparam TAG_W  = 22;

    // Byte address layout for a 1 KB cache (64 lines x 4 words x 4 bytes):
    //   [1:0] byte-in-word  [3:2] word-in-line  [9:4] line index  [31:10] tag
    wire [IDX_W-1:0]   idx  = cpu_addr[9:4];
    wire [TAG_W-1:0]   tag  = cpu_addr[31:10];
    wire [WORD_W-1:0]  word = cpu_addr[3:2];
    wire [31:0] line_base  = { cpu_addr[31:4], 4'b0000 };

    reg                       valid [0:LINES-1];
    reg [TAG_W-1:0]           tagv [0:LINES-1];
    reg [31:0]                data [0:LINES-1][0:LINE_WORDS-1];

    reg [IDX_W-1:0]           r_idx;
    reg [TAG_W-1:0]           r_tag;
    reg [WORD_W-1:0]          r_word;
    reg [31:0]                r_line_base;
    reg [31:0]                r_buf [0:LINE_WORDS-1];

    localparam S_IDLE    = 2'd0;
    localparam S_ISSUE   = 2'd1;
    localparam S_CAPTURE = 2'd2;
    localparam S_COMMIT  = 2'd3;
    reg [1:0] state;

    // Combinational hit/ready: when idle and the line is present, the fetch
    // is ready this cycle (rdata registered, appears next cycle, matching
    // boot_rom's 1-cycle latency). During refill, ready=0.
    wire hit = valid[idx] && (tagv[idx] == tag);
    wire idle = (state == S_IDLE);
    assign cpu_ready = idle & hit;
    assign cpu_rdata = data[idx][word];

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < LINES; i = i + 1) valid[i] <= 1'b0;
            state <= S_IDLE;
            be_addr <= 32'b0;
            r_word <= 0;
            r_line_base <= 32'b0;
            access_count <= 32'b0;
            hit_count <= 32'b0;
            miss_count <= 32'b0;
            refill_cycle_count <= 32'b0;
        end else if (invalidate) begin
            for (i = 0; i < LINES; i = i + 1) valid[i] <= 1'b0;
            access_count <= 32'b0;
            hit_count <= 32'b0;
            miss_count <= 32'b0;
            refill_cycle_count <= 32'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    access_count <= access_count + 32'd1;
                    if (hit) begin
                        hit_count <= hit_count + 32'd1;
                    end else begin
                        miss_count <= miss_count + 32'd1;
                        // Issue first refill beat (word 0 of the line).
                        be_addr <= line_base;
                        r_idx   <= idx;
                        r_tag   <= tag;
                        r_word  <= 0;
                        r_line_base <= line_base;
                        state   <= S_ISSUE;
                    end
                    // On hit, do nothing: cpu_rdata is combinational from the
                    // array and cpu_ready=1. The CPU advances PC normally.
                end
                S_ISSUE: begin
                    // boot_rom is synchronous; wait one cycle after be_addr.
                    refill_cycle_count <= refill_cycle_count + 32'd1;
                    state <= S_CAPTURE;
                end
                S_CAPTURE: begin
                    // be_rdata this cycle is beat[r_word].
                    r_buf[r_word] <= be_rdata;
                    if (r_word == (LINE_WORDS-1)) begin
                        state <= S_COMMIT;
                    end else begin
                        be_addr <= r_line_base + ((r_word + 1'b1) << 2);
                        r_word  <= r_word + 1'b1;
                        state <= S_ISSUE;
                    end
                end
                S_COMMIT: begin
                    // Commit the filled line. All 4 beats now in r_buf.
                    for (i = 0; i < LINE_WORDS; i = i + 1)
                        data[r_idx][i] <= r_buf[i];
                    tagv[r_idx] <= r_tag;
                    valid[r_idx] <= 1'b1;
                    state <= S_IDLE;
                    // After this cycle, idle&hit will be true and cpu_ready
                    // asserts; the requested word is returned next cycle.
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
