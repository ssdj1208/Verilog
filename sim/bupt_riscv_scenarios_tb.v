`timescale 1ns / 1ps

module bupt_riscv_scenarios_tb();
    reg clk;
    reg rst;
    reg[15:0] panel_switches;
    wire[31:0] live_result;
    wire stall_loaduse;
    wire stall_muldiv;
    wire stall_dcache;
    wire stall_ifetch;
    wire flush_branch;
    wire flush_trap;

    wire ddr_valid;
    wire ddr_we;
    wire[3:0] ddr_wstrb;
    wire[26:0] ddr_addr;
    wire[31:0] ddr_wdata;
    wire ddr_ready;
    wire ddr_resp_valid;
    wire[31:0] ddr_rdata;
    wire ddr_calib_done;
    wire ddr_busy;

    integer scenario;
    integer timeout;
    reg seen_event;
    reg seen_forward;

    soc #(
        .UART_CLKS_PER_BIT(16),
        .TIMER_TICK_CYCLES(32'd1000)
    ) dut(
        .clk(clk), .bus_clk(clk), .rst(rst),
        .panel_switches_i(panel_switches),
        .uart_rx_i(1'b1), .uart_tx_o(), .led(),
        .acceptance_active(), .acceptance_status(), .acceptance_fail(),
        .acceptance_live_result(live_result),
        .acceptance_display_value(), .acceptance_display_dp(),
        .ddr_backend_valid(ddr_valid), .ddr_backend_we(ddr_we),
        .ddr_backend_wstrb(ddr_wstrb), .ddr_backend_addr(ddr_addr),
        .ddr_backend_wdata(ddr_wdata), .ddr_backend_ready(ddr_ready),
        .ddr_backend_resp_valid(ddr_resp_valid),
        .ddr_backend_resp_rdata(ddr_rdata),
        .ddr_backend_calib_done(ddr_calib_done), .ddr_backend_busy(ddr_busy),
        .debug_writedata(), .debug_dataadr(), .debug_memwrite(),
        .uart_tx_ready(), .uart_rx_valid(),
        .demo_pcF(), .demo_pcD(), .demo_pcE(), .demo_pcM(), .demo_pcW(),
        .demo_instrF(), .demo_instrD(), .demo_instrE(), .demo_instrM(), .demo_instrW(),
        .demo_validF(), .demo_validD(), .demo_validE(), .demo_validM(), .demo_validW(),
        .demo_stallF(), .demo_stallD(),
        .demo_stall_loaduse(stall_loaduse),
        .demo_stall_muldiv(stall_muldiv),
        .demo_stall_dcache(stall_dcache),
        .demo_stall_ifetch(stall_ifetch),
        .demo_flush_branch(flush_branch),
        .demo_flush_trap(flush_trap)
        );

    ddr_model #(
        .ADDR_WIDTH(12), .CALIB_CYCLES(32),
        .READ_LATENCY(7), .WRITE_LATENCY(5)
    ) ddr(
        .clk(clk), .rst(rst), .req_valid(ddr_valid), .req_we(ddr_we),
        .req_wstrb(ddr_wstrb), .req_addr(ddr_addr), .req_wdata(ddr_wdata),
        .req_ready(ddr_ready), .resp_valid(ddr_resp_valid), .resp_rdata(ddr_rdata),
        .init_calib_complete(ddr_calib_done), .busy(ddr_busy)
        );

    always #5 clk = ~clk;

    task verify_scenario;
        input integer selected;
        begin
            panel_switches = 16'h8000 | (selected << 3);
            seen_event = 1'b0;
            seen_forward = 1'b0;
            for (timeout = 0; timeout < 250000; timeout = timeout + 1) begin
                @(posedge clk);
                if (dut.perf_forward) seen_forward = 1'b1;
                case (selected)
                    1: if (seen_forward && live_result[15:0] == 16'd8) seen_event = 1'b1;
                    2: if (stall_loaduse && live_result[15:0] == 16'd13) seen_event = 1'b1;
                    3: if (stall_muldiv && live_result == 32'h002a0007) seen_event = 1'b1;
                    4: if (flush_branch && live_result != 32'b0) seen_event = 1'b1;
                    5: if (stall_dcache && live_result != 32'b0) seen_event = 1'b1;
                    6: if (stall_ifetch && live_result != 32'b0) seen_event = 1'b1;
                    7: if (flush_trap && live_result != 32'b0) seen_event = 1'b1;
                    default: seen_event = 1'b0;
                endcase
                if (seen_event) timeout = 250000;
            end
            if (!seen_event) begin
                $display("Simulation Failed: scenario %0d incomplete result=%h lu=%b md=%b dc=%b if=%b br=%b tr=%b fwd=%b pc=%h",
                         selected, live_result, stall_loaduse, stall_muldiv,
                         stall_dcache, stall_ifetch, flush_branch, flush_trap,
                         seen_forward, dut.pc);
                $finish;
            end
            repeat (8) @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        panel_switches = 16'h8000;
        #100 rst = 1'b0;
        wait (ddr_calib_done);
        repeat (100) @(posedge clk);

        for (scenario = 1; scenario <= 7; scenario = scenario + 1) begin
            verify_scenario(scenario);
        end

        panel_switches = 16'h8000 | (8 << 3);
        for (timeout = 0; timeout < 10000 && live_result[31:16] != 16'hbad5;
             timeout = timeout + 1) begin
            @(posedge clk);
        end
        if (live_result[31:16] != 16'hbad5) begin
            $display("Simulation Failed: reserved scenario result mismatch %h", live_result);
            $finish;
        end

        $display("Simulation succeeded: enhanced pipeline scenarios verified");
        $finish;
    end
endmodule
