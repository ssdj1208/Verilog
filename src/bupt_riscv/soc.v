`timescale 1ns / 1ps

module soc #(
    parameter UART_CLKS_PER_BIT = 868,
    parameter TIMER_TICK_CYCLES = 32'd1000000 // ~10 ms at 100 MHz
)(
    input wire clk,
    input wire bus_clk,
    input wire rst,
    input wire[15:0] panel_switches_i,
    input wire uart_rx_i,
    output wire uart_tx_o,
    output wire[15:0] led,

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

    output wire[31:0] debug_writedata,
    output wire[31:0] debug_dataadr,
    output wire debug_memwrite,
    output wire uart_tx_ready,
    output wire uart_rx_valid,
    output wire[31:0] demo_pcF,
    output wire[31:0] demo_pcD,
    output wire[31:0] demo_pcE,
    output wire[31:0] demo_pcM,
    output wire[31:0] demo_pcW,
    output wire[31:0] demo_instrF,
    output wire[31:0] demo_instrD,
    output wire[31:0] demo_instrE,
    output wire[31:0] demo_instrM,
    output wire[31:0] demo_instrW,
    output wire demo_validF,
    output wire demo_validD,
    output wire demo_validE,
    output wire demo_validM,
    output wire demo_validW,
    output wire demo_stallF,
    output wire demo_stallD,
    output wire demo_stall_loaduse,
    output wire demo_stall_muldiv,
    output wire demo_stall_dcache,
    output wire demo_stall_ifetch,
    output wire demo_flush_branch,
    output wire demo_flush_trap
    );

    wire[31:0] pc;
    wire[31:0] instr;
    wire i_ready;
    wire memvalid;
    wire memready;
    wire memwrite;
    wire[3:0] wstrb;
    wire[31:0] dataadr;
    wire[31:0] writedata;
    wire[31:0] readdata;
    wire[7:0] irq_lines;

    wire perf_retireW;
    wire perf_branchE;
    wire perf_mispredictE;
    wire perf_stall;
    wire perf_stall_loaduse;
    wire perf_stall_muldiv;
    wire perf_stall_dcache;
    wire perf_stall_ifetch;
    wire perf_flush_branch;
    wire perf_flush_trap;
    wire[31:0] debug_branch_pc;
    wire[31:0] debug_branch_srca;
    wire[31:0] debug_branch_srcb;
    wire[31:0] debug_branch_info;
    reg[3:0] demo_loaduse_history_r;
    reg demo_loaduse_seen_r;
    reg[3:0] demo_muldiv_history_r;
    reg[3:0] demo_dcache_history_r;
    reg[3:0] demo_ifetch_history_r;
    reg[3:0] demo_branch_history_r;
    reg[3:0] demo_trap_history_r;
    wire[6:0] demo_opcodeD = demo_instrD[6:0];
    wire[6:0] demo_opcodeE = demo_instrE[6:0];
    wire[4:0] demo_load_rdE = demo_instrE[11:7];
    wire demo_uses_rs1D =
        (demo_opcodeD == 7'b0110011) || // OP
        (demo_opcodeD == 7'b0010011) || // OP-IMM
        (demo_opcodeD == 7'b0000011) || // LOAD
        (demo_opcodeD == 7'b0100011) || // STORE
        (demo_opcodeD == 7'b1100011) || // BRANCH
        (demo_opcodeD == 7'b1100111);   // JALR
    wire demo_uses_rs2D =
        (demo_opcodeD == 7'b0110011) || // OP
        (demo_opcodeD == 7'b0100011) || // STORE
        (demo_opcodeD == 7'b1100011);   // BRANCH
    wire demo_loaduse_dependency =
        demo_validD && demo_validE &&
        (demo_opcodeE == 7'b0000011) &&
        (demo_load_rdE != 5'b0) &&
        ((demo_uses_rs1D && (demo_instrD[19:15] == demo_load_rdE)) ||
         (demo_uses_rs2D && (demo_instrD[24:20] == demo_load_rdE)));
    wire demo_loaduse_event = perf_stall_loaduse | demo_loaduse_dependency;

    riscv cpu(
        .clk(clk),
        .rst(rst),
        .irq(irq_lines),
        .pcF(pc),
        .instrF(instr),
        .i_readyF(i_ready),
        .d_validM(memvalid),
        .d_readyM(memready),
        .memwriteM(memwrite),
        .wstrbM(wstrb),
        .aluoutM(dataadr),
        .writedataM(writedata),
        .readdataM(readdata),
        .perf_retireW(perf_retireW),
        .perf_branchE(perf_branchE),
        .perf_mispredictE(perf_mispredictE),
        .perf_stall(perf_stall),
        .perf_stall_loaduse(perf_stall_loaduse),
        .perf_stall_muldiv(perf_stall_muldiv),
        .perf_stall_dcache(perf_stall_dcache),
        .perf_stall_ifetch(perf_stall_ifetch),
        .perf_flush_branch(perf_flush_branch),
        .perf_flush_trap(perf_flush_trap),
        .demo_pcF(demo_pcF),
        .demo_pcD(demo_pcD),
        .demo_pcE(demo_pcE),
        .demo_pcM(demo_pcM),
        .demo_pcW(demo_pcW),
        .demo_instrF(demo_instrF),
        .demo_instrD(demo_instrD),
        .demo_instrE(demo_instrE),
        .demo_instrM(demo_instrM),
        .demo_instrW(demo_instrW),
        .demo_validF(demo_validF),
        .demo_validD(demo_validD),
        .demo_validE(demo_validE),
        .demo_validM(demo_validM),
        .demo_validW(demo_validW),
        .demo_stallF(demo_stallF),
        .demo_stallD(demo_stallD),
        .debug_branch_pc(debug_branch_pc),
        .debug_branch_srca(debug_branch_srca),
        .debug_branch_srcb(debug_branch_srcb),
        .debug_branch_info(debug_branch_info)
        );

    simple_bus #(
        .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .TIMER_TICK_CYCLES(TIMER_TICK_CYCLES)
    ) bus(
        .clk(bus_clk),
        .perf_clk(clk),
        .rst(rst),
        .i_addr(pc),
        .i_rdata(instr),
        .i_ready(i_ready),
        .d_valid(memvalid),
        .d_ready(memready),
        .d_we(memwrite),
        .d_wstrb(wstrb),
        .d_addr(dataadr),
        .d_wdata(writedata),
        .d_rdata(readdata),
        .ddr_backend_valid(ddr_backend_valid),
        .ddr_backend_we(ddr_backend_we),
        .ddr_backend_wstrb(ddr_backend_wstrb),
        .ddr_backend_addr(ddr_backend_addr),
        .ddr_backend_wdata(ddr_backend_wdata),
        .ddr_backend_ready(ddr_backend_ready),
        .ddr_backend_resp_valid(ddr_backend_resp_valid),
        .ddr_backend_resp_rdata(ddr_backend_resp_rdata),
        .ddr_backend_calib_done(ddr_backend_calib_done),
        .ddr_backend_busy(ddr_backend_busy),
        .panel_switches_i(panel_switches_i),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .led(led),
        .uart_tx_ready(uart_tx_ready),
        .uart_rx_valid(uart_rx_valid),
        .irq_lines(irq_lines),
        .perf_retireW(perf_retireW),
        .perf_branchE(perf_branchE),
        .perf_mispredictE(perf_mispredictE),
        .perf_stall(perf_stall),
        .perf_stall_loaduse(perf_stall_loaduse),
        .perf_stall_muldiv(perf_stall_muldiv),
        .perf_stall_dcache(perf_stall_dcache),
        .perf_stall_ifetch(perf_stall_ifetch),
        .perf_flush_branch(perf_flush_branch),
        .perf_flush_trap(perf_flush_trap),
        .debug_branch_pc(debug_branch_pc),
        .debug_branch_srca(debug_branch_srca),
        .debug_branch_srcb(debug_branch_srcb),
        .debug_branch_info(debug_branch_info)
        );

    assign debug_writedata = writedata;
    assign debug_dataadr = dataadr;
    assign debug_memwrite = memwrite;

    always @(posedge clk) begin
        if (rst) begin
            demo_loaduse_history_r <= 4'b0;
            demo_loaduse_seen_r <= 1'b0;
            demo_muldiv_history_r <= 4'b0;
            demo_dcache_history_r <= 4'b0;
            demo_ifetch_history_r <= 4'b0;
            demo_branch_history_r <= 4'b0;
            demo_trap_history_r <= 4'b0;
        end else begin
            demo_loaduse_history_r <= {demo_loaduse_history_r[2:0], demo_loaduse_event};
            if (demo_loaduse_event) begin
                demo_loaduse_seen_r <= 1'b1;
            end
            demo_muldiv_history_r <= {demo_muldiv_history_r[2:0], perf_stall_muldiv};
            demo_dcache_history_r <= {demo_dcache_history_r[2:0], perf_stall_dcache};
            demo_ifetch_history_r <= {demo_ifetch_history_r[2:0], perf_stall_ifetch};
            demo_branch_history_r <= {demo_branch_history_r[2:0], perf_flush_branch};
            demo_trap_history_r <= {demo_trap_history_r[2:0], perf_flush_trap};
        end
    end

    assign demo_stall_loaduse = demo_loaduse_event | (|demo_loaduse_history_r) | demo_loaduse_seen_r;
    assign demo_stall_muldiv = perf_stall_muldiv | (|demo_muldiv_history_r);
    assign demo_stall_dcache = perf_stall_dcache | (|demo_dcache_history_r);
    assign demo_stall_ifetch = perf_stall_ifetch | (|demo_ifetch_history_r);
    assign demo_flush_branch = perf_flush_branch | (|demo_branch_history_r);
    assign demo_flush_trap = perf_flush_trap | (|demo_trap_history_r);
endmodule
