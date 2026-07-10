`timescale 1ns / 1ps

module bupt_riscv_demo_tb();
    reg clk;
    reg rst;
    reg run_toggle;
    reg step_pulse;
    reg speed_toggle;

    wire soc_clk;
    wire bus_clk;
    wire soc_rst;
    reg [3:0] rst_sync;

    wire uart_tx_o;
    wire[15:0] led;
    wire[31:0] debug_writedata;
    wire[31:0] debug_dataadr;
    wire debug_memwrite;
    wire uart_tx_ready;
    wire uart_rx_valid;
    wire[31:0] demo_pcF;
    wire[31:0] demo_pcD;
    wire[31:0] demo_pcE;
    wire[31:0] demo_pcM;
    wire[31:0] demo_pcW;
    wire demo_validF;
    wire demo_validD;
    wire demo_validE;
    wire demo_validM;
    wire demo_validW;
    wire demo_stallF;
    wire demo_stallD;
    wire demo_stall_loaduse;
    wire demo_stall_muldiv;
    wire demo_stall_dcache;
    wire demo_stall_ifetch;
    wire demo_flush_branch;
    wire demo_flush_trap;
    wire demo_run_active;
    wire demo_speed_sel;

    integer timeout_cycles;
    integer soc_edge_count;
    integer edge_count_before;
    integer step_i;
    integer progressed_steps;
    reg seen_loaduse;
    reg seen_loaduse_hold;
    reg seen_loaduse_dependency;
    reg check_loaduse_hold;
    reg seen_muldiv;
    reg seen_flush;
    reg[159:0] prev_pipe_vec;
    reg[159:0] curr_pipe_vec;

    assign bus_clk = soc_clk;
    assign soc_rst = rst_sync[3];

    demo_clock_ctrl #(
        .SLOW_DIV(8),
        .FAST_DIV(3),
        .STARTUP_PULSES(14)
    ) demo_ctrl(
        .clk_i(clk),
        .rst_i(rst),
        .demo_mode_i(1'b1),
        .run_toggle_i(run_toggle),
        .step_i(step_pulse),
        .speed_toggle_i(speed_toggle),
        .soc_clk_o(soc_clk),
        .run_active_o(demo_run_active),
        .speed_sel_o(demo_speed_sel)
        );

    soc #(
        .UART_CLKS_PER_BIT(16),
        .TIMER_TICK_CYCLES(32'd50000)
    ) dut(
        .clk(soc_clk),
        .bus_clk(bus_clk),
        .rst(soc_rst),
        .panel_switches_i(16'h8000),
        .uart_rx_i(1'b1),
        .uart_tx_o(uart_tx_o),
        .led(led),
        .ddr_backend_valid(),
        .ddr_backend_we(),
        .ddr_backend_wstrb(),
        .ddr_backend_addr(),
        .ddr_backend_wdata(),
        .ddr_backend_ready(1'b0),
        .ddr_backend_resp_valid(1'b0),
        .ddr_backend_resp_rdata(32'b0),
        .ddr_backend_calib_done(1'b1),
        .ddr_backend_busy(1'b0),
        .debug_writedata(debug_writedata),
        .debug_dataadr(debug_dataadr),
        .debug_memwrite(debug_memwrite),
        .uart_tx_ready(uart_tx_ready),
        .uart_rx_valid(uart_rx_valid),
        .demo_pcF(demo_pcF),
        .demo_pcD(demo_pcD),
        .demo_pcE(demo_pcE),
        .demo_pcM(demo_pcM),
        .demo_pcW(demo_pcW),
        .demo_validF(demo_validF),
        .demo_validD(demo_validD),
        .demo_validE(demo_validE),
        .demo_validM(demo_validM),
        .demo_validW(demo_validW),
        .demo_stallF(demo_stallF),
        .demo_stallD(demo_stallD),
        .demo_stall_loaduse(demo_stall_loaduse),
        .demo_stall_muldiv(demo_stall_muldiv),
        .demo_stall_dcache(demo_stall_dcache),
        .demo_stall_ifetch(demo_stall_ifetch),
        .demo_flush_branch(demo_flush_branch),
        .demo_flush_trap(demo_flush_trap)
        );

    always @(posedge soc_clk or posedge rst) begin
        if (rst) begin
            rst_sync <= 4'hf;
            soc_edge_count <= 0;
        end else begin
            rst_sync <= {rst_sync[2:0], 1'b0};
            soc_edge_count <= soc_edge_count + 1;
        end
    end

    initial begin
        clk <= 1'b0;
        forever #5 clk <= ~clk;
    end

    initial begin
        rst <= 1'b1;
        run_toggle <= 1'b0;
        step_pulse <= 1'b0;
        speed_toggle <= 1'b0;
        timeout_cycles <= 0;
        #100;
        rst <= 1'b0;
    end

    always @(posedge clk) begin
        if (!rst) begin
            timeout_cycles <= timeout_cycles + 1;
            if (timeout_cycles > 2000000) begin
                $display("Simulation Failed: demo timeout");
                $finish;
            end
        end
    end

    task step_once;
        begin
            @(negedge clk);
            step_pulse = 1'b1;
            @(posedge clk);
            #1 step_pulse = 1'b0;
            @(posedge soc_clk);
            @(posedge clk);
        end
    endtask

    task toggle_run;
        begin
            @(negedge clk);
            run_toggle = 1'b1;
            @(negedge clk);
            run_toggle = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task toggle_speed;
        begin
            @(negedge clk);
            speed_toggle = 1'b1;
            @(negedge clk);
            speed_toggle = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        wait (rst == 1'b0);
        wait (soc_rst == 1'b0);
        repeat (20) @(posedge clk);

        if (demo_run_active !== 1'b0) begin
            $display("Simulation Failed: demo controller should start paused");
            $finish;
        end

        toggle_speed();
        if (demo_speed_sel !== 1'b1) begin
            $display("Simulation Failed: demo speed toggle did not select fast mode");
            $finish;
        end
        toggle_speed();
        if (demo_speed_sel !== 1'b0) begin
            $display("Simulation Failed: demo speed toggle did not restore slow mode");
            $finish;
        end

        edge_count_before = soc_edge_count;
        toggle_run();
        if (demo_run_active !== 1'b1) begin
            $display("Simulation Failed: demo run toggle did not start execution");
            $finish;
        end
        repeat (24) @(posedge clk);
        if (soc_edge_count <= edge_count_before) begin
            $display("Simulation Failed: demo run mode produced no SoC clocks");
            $finish;
        end
        toggle_run();
        if (demo_run_active !== 1'b0) begin
            $display("Simulation Failed: demo run toggle did not pause execution");
            $finish;
        end

        edge_count_before = soc_edge_count;
        step_once();
        repeat (2) @(posedge clk);
        if (soc_edge_count != (edge_count_before + 1)) begin
            $display("Simulation Failed: one step produced %0d SoC clocks", soc_edge_count - edge_count_before);
            $finish;
        end

        seen_loaduse = 1'b0;
        seen_loaduse_hold = 1'b0;
        seen_loaduse_dependency = 1'b0;
        check_loaduse_hold = 1'b0;
        seen_muldiv = 1'b0;
        seen_flush = 1'b0;
        progressed_steps = 0;
        prev_pipe_vec = {demo_pcF, demo_pcD, demo_pcE, demo_pcM, demo_pcW};

        for (step_i = 0; step_i < 160; step_i = step_i + 1) begin
            step_once();
            curr_pipe_vec = {demo_pcF, demo_pcD, demo_pcE, demo_pcM, demo_pcW};
            if ((curr_pipe_vec != prev_pipe_vec) || demo_stallD || demo_stall_muldiv) begin
                progressed_steps = progressed_steps + 1;
            end
            prev_pipe_vec = curr_pipe_vec;

            if (check_loaduse_hold) begin
                if (!demo_stall_loaduse) begin
                    $display("Simulation Failed: load-use event was not held for the next CPU cycle");
                    $finish;
                end
                seen_loaduse_hold = 1'b1;
                check_loaduse_hold = 1'b0;
            end
            if (dut.perf_stall_loaduse) begin
                seen_loaduse = 1'b1;
                check_loaduse_hold = 1'b1;
            end
            if (dut.demo_loaduse_dependency) begin
                seen_loaduse_dependency = 1'b1;
            end
            if (demo_stall_muldiv) begin
                seen_muldiv = 1'b1;
            end
            if (demo_flush_branch) begin
                seen_flush = 1'b1;
            end

            if (seen_loaduse && seen_loaduse_hold && seen_loaduse_dependency && seen_muldiv && seen_flush && (progressed_steps > 8)) begin
                if (!demo_stall_loaduse) begin
                    $display("Simulation Failed: load-use seen latch cleared before reset");
                    $finish;
                end
                $display("Simulation succeeded: pipeline demo stepping verified");
                $finish;
            end
        end

        $display("Simulation Failed: demo checks incomplete loaduse=%0d hold=%0d dependency=%0d muldiv=%0d flush=%0d progressed=%0d",
                 seen_loaduse, seen_loaduse_hold, seen_loaduse_dependency, seen_muldiv, seen_flush, progressed_steps);
        $finish;
    end
endmodule
