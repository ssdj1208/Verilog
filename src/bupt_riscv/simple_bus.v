`timescale 1ns / 1ps

module simple_bus #(
    parameter UART_CLKS_PER_BIT = 868,
    parameter TIMER_TICK_CYCLES = 32'd50000000
)(
    input wire clk,
    input wire perf_clk,
    input wire rst,

    input wire[31:0] i_addr,
    output wire[31:0] i_rdata,

    input wire d_valid,
    output wire d_ready,
    input wire d_we,
    input wire[3:0] d_wstrb,
    input wire[31:0] d_addr,
    input wire[31:0] d_wdata,
    output wire[31:0] d_rdata,

    output wire ddr_backend_valid,
    output wire ddr_backend_we,
    output wire[3:0] ddr_backend_wstrb,
    output wire[26:0] ddr_backend_addr,
    output wire[31:0] ddr_backend_wdata,
    input wire ddr_backend_ready,
    input wire ddr_backend_resp_valid,
    input wire[31:0] ddr_backend_resp_rdata,
    input wire ddr_backend_calib_done,
    input wire ddr_backend_busy,

    input wire uart_rx_i,
    output wire uart_tx_o,
    output wire[15:0] led,

    output wire uart_tx_ready,
    output wire uart_rx_valid,
    output wire[7:0] irq_lines,
    input wire perf_retireW,
    input wire perf_branchE,
    input wire perf_mispredictE,
    input wire perf_stall,
    input wire[31:0] debug_branch_pc,
    input wire[31:0] debug_branch_srca,
    input wire[31:0] debug_branch_srcb,
    input wire[31:0] debug_branch_info
    );

    wire boot_sel_i = (i_addr[31:14] == 18'h00000);
    wire boot_sel_d = (d_addr[31:14] == 18'h00000);
    wire ram_sel_d  = (d_addr[31:16] == 16'h0001);
    wire gpio_sel_d = (d_addr[31:8] == 24'h100000);
    wire uart_sel_d = (d_addr[31:8] == 24'h100010);
    wire timer_sel_d = (d_addr[31:8] == 24'h100020);
    wire irq_sel_d   = (d_addr[31:8] == 24'h100030);
    wire ddr_status_sel_d = (d_addr[31:8] == 24'h100040);
    wire perf_sel_d = (d_addr[31:8] == 24'h100050);
    wire cache_sel_d = (d_addr[31:8] == 24'h100060);
    wire fp_sel_d = (d_addr[31:8] == 24'h100070);
    wire debug_sel_d = (d_addr[31:8] == 24'h100080);
    wire ddr_sel_d = (d_addr[31:27] == 5'b10000);

    wire ddr_ready;
    wire[31:0] ddr_rdata;
    wire ddr_calib_done;
    wire ddr_busy;
    wire cache_ready;
    wire[31:0] cache_rdata;
    wire cache_mem_valid;
    wire cache_mem_we;
    wire[3:0] cache_mem_wstrb;
    wire[31:0] cache_mem_addr;
    wire[31:0] cache_mem_wdata;
    wire[31:0] cache_accesses;
    wire[31:0] cache_hits;
    wire[31:0] cache_misses;
    wire[31:0] cache_replacements;
    wire cache_clear_stats = d_we & cache_sel_d & |d_wstrb & (d_addr[4:0] == 5'h1c) & d_wdata[0];

    wire d_re = ~d_we;

    wire[31:0] boot_i_rdata;
    wire[31:0] boot_d_rdata;
    wire[31:0] ram_rdata;
    wire[31:0] gpio_rdata;
    wire[31:0] uart_rdata;
    wire[31:0] timer_rdata;
    wire[31:0] irq_rdata;
    wire[31:0] perf_rdata;
    reg[31:0] cache_mmio_rdata;
    reg[31:0] debug_rdata;
    wire[31:0] fp_rdata;
    wire timer_irq;

    boot_rom iboot(
        .clk(clk),
        .a(i_addr[13:2]),
        .spo(boot_i_rdata)
        );

    boot_rom dboot(
        .clk(clk),
        .a(d_addr[13:2]),
        .spo(boot_d_rdata)
        );

    bram_ram #(.ADDR_WIDTH(10)) ram(
        .clk(clk),
        .we(d_we & ram_sel_d),
        .wstrb(d_wstrb),
        .word_addr(d_addr[11:2]),
        .wdata(d_wdata),
        .rdata(ram_rdata)
        );

    gpio_mmio gpio(
        .clk(clk),
        .rst(rst),
        .we(d_we & gpio_sel_d & |d_wstrb),
        .wdata(d_wdata),
        .rdata(gpio_rdata),
        .led(led)
        );

    uart_mmio #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) uart(
        .clk(clk),
        .rst(rst),
        .we(d_we & uart_sel_d & |d_wstrb),
        .re(d_re & uart_sel_d),
        .wstrb(d_wstrb),
        .addr(d_addr[3:0]),
        .wdata(d_wdata),
        .rdata(uart_rdata),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .tx_ready(uart_tx_ready),
        .rx_valid(uart_rx_valid)
        );

    timer_mmio #(.DEFAULT_COMPARE(TIMER_TICK_CYCLES)) timer(
        .clk(clk),
        .rst(rst),
        .we(d_we & timer_sel_d & |d_wstrb),
        .re(d_re & timer_sel_d),
        .wstrb(d_wstrb),
        .addr(d_addr[3:0]),
        .wdata(d_wdata),
        .rdata(timer_rdata),
        .irq(timer_irq)
        );

    irq_controller irqc(
        .clk(clk),
        .rst(rst),
        .we(d_we & irq_sel_d & |d_wstrb),
        .re(d_re & irq_sel_d),
        .wstrb(d_wstrb),
        .addr(d_addr[3:0]),
        .wdata(d_wdata),
        .rdata(irq_rdata),
        .timer_irq(timer_irq),
        .irq_lines(irq_lines)
        );

    perf_mmio perf(
        .clk(perf_clk),
        .rst(rst),
        .we(d_we & perf_sel_d & |d_wstrb),
        .re(d_re & perf_sel_d),
        .addr(d_addr[4:0]),
        .wdata(d_wdata),
        .rdata(perf_rdata),
        .retire(perf_retireW),
        .branch(perf_branchE),
        .mispredict(perf_mispredictE),
        .stall(perf_stall)
        );

    fp_mmio fp(
        .clk(clk),
        .rst(rst),
        .we(d_we & fp_sel_d & |d_wstrb),
        .re(d_re & fp_sel_d),
        .addr(d_addr[4:0]),
        .wdata(d_wdata),
        .rdata(fp_rdata)
        );

    always @(*) begin
        case (d_addr[4:0])
            5'h00: cache_mmio_rdata = cache_accesses;
            5'h04: cache_mmio_rdata = cache_hits;
            5'h08: cache_mmio_rdata = cache_misses;
            5'h0c: cache_mmio_rdata = cache_replacements;
            5'h10: cache_mmio_rdata = 32'h0002_0010; // 2-way, 16 sets
            5'h14: cache_mmio_rdata = 32'd1; // policy 1 = LRU
            default: cache_mmio_rdata = 32'b0;
        endcase
    end

    always @(*) begin
        case (d_addr[4:0])
            5'h00: debug_rdata = debug_branch_pc;
            5'h04: debug_rdata = debug_branch_srca;
            5'h08: debug_rdata = debug_branch_srcb;
            5'h0c: debug_rdata = debug_branch_info;
            default: debug_rdata = 32'b0;
        endcase
    end

    dcache_2way_lru dcache(
        .clk(clk),
        .rst(rst),
        .cpu_valid(d_valid & ddr_sel_d),
        .cpu_we(d_we),
        .cpu_wstrb(d_wstrb),
        .cpu_addr(d_addr),
        .cpu_wdata(d_wdata),
        .cpu_ready(cache_ready),
        .cpu_rdata(cache_rdata),
        .mem_valid(cache_mem_valid),
        .mem_we(cache_mem_we),
        .mem_wstrb(cache_mem_wstrb),
        .mem_addr(cache_mem_addr),
        .mem_wdata(cache_mem_wdata),
        .mem_ready(ddr_ready),
        .mem_rdata(ddr_rdata),
        .clear_stats(cache_clear_stats),
        .access_count(cache_accesses),
        .hit_count(cache_hits),
        .miss_count(cache_misses),
        .replacement_count(cache_replacements)
        );

    ddr_bridge ddr(
        .clk(clk),
        .rst(rst),
        .cpu_valid(cache_mem_valid),
        .cpu_we(cache_mem_we),
        .cpu_wstrb(cache_mem_wstrb),
        .cpu_addr(cache_mem_addr),
        .cpu_wdata(cache_mem_wdata),
        .cpu_ready(ddr_ready),
        .cpu_rdata(ddr_rdata),
        .calib_done(ddr_calib_done),
        .busy(ddr_busy),
        .backend_valid(ddr_backend_valid),
        .backend_we(ddr_backend_we),
        .backend_wstrb(ddr_backend_wstrb),
        .backend_addr(ddr_backend_addr),
        .backend_wdata(ddr_backend_wdata),
        .backend_ready(ddr_backend_ready),
        .backend_resp_valid(ddr_backend_resp_valid),
        .backend_resp_rdata(ddr_backend_resp_rdata),
        .backend_calib_done(ddr_backend_calib_done),
        .backend_busy(ddr_backend_busy)
        );


    assign i_rdata = boot_sel_i ? boot_i_rdata : 32'b0;

    // Local regions remain single-cycle ready. The DDR region can stretch the
    // CPU M stage through d_ready=0 until ddr_bridge completes the transaction.
    assign d_ready = ~d_valid ? 1'b1 :
                     ddr_sel_d ? cache_ready : 1'b1;

    assign d_rdata = boot_sel_d       ? boot_d_rdata :
                     ram_sel_d        ? ram_rdata :
                     gpio_sel_d       ? gpio_rdata :
                     uart_sel_d       ? uart_rdata :
                     timer_sel_d      ? timer_rdata :
                     irq_sel_d        ? irq_rdata :
                     perf_sel_d       ? perf_rdata :
                     cache_sel_d      ? cache_mmio_rdata :
                     fp_sel_d         ? fp_rdata :
                     debug_sel_d      ? debug_rdata :
                     ddr_status_sel_d ? {30'b0, ddr_busy, ddr_calib_done} :
                     ddr_sel_d        ? cache_rdata : 32'b0;
endmodule
