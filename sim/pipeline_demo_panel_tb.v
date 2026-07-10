`timescale 1ns / 1ps

module pipeline_demo_panel_tb();
    reg clk;
    reg rst;
    reg page_toggle;
    reg[2:0] stage_sel;
    reg stall_loaduse;
    wire[15:0] led;
    wire[7:0] an;
    wire[6:0] seg;
    wire dp;
    wire page;

    pipeline_demo_panel dut(
        .clk(clk),
        .rst(rst),
        .demo_mode_i(1'b1),
        .page_toggle_i(page_toggle),
        .stage_sel_i(stage_sel),
        .run_active_i(1'b0),
        .speed_sel_i(1'b1),
        .pcF_i(32'h00000001),
        .pcD_i(32'h00000002),
        .pcE_i(32'h1234567a),
        .pcM_i(32'h00000003),
        .pcW_i(32'h00000004),
        .instrF_i(32'h00000011),
        .instrD_i(32'h00000022),
        .instrE_i(32'h89abcdef),
        .instrM_i(32'h00000033),
        .instrW_i(32'h00000044),
        .validF_i(1'b1),
        .validD_i(1'b0),
        .validE_i(1'b1),
        .validM_i(1'b0),
        .validW_i(1'b1),
        .stall_loaduse_i(stall_loaduse),
        .stall_muldiv_i(1'b0),
        .stall_ifetch_i(1'b1),
        .stall_dcache_i(1'b0),
        .flush_branch_i(1'b1),
        .flush_trap_i(1'b0),
        .led_o(led),
        .an_o(an),
        .seg_o(seg),
        .dp_o(dp),
        .page_o(page)
        );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 1'b1;
        page_toggle = 1'b0;
        stage_sel = 3'd2;
        stall_loaduse = 1'b1;
        #20;
        rst = 1'b0;
        #1;

        force dut.scan_div_r = 16'h0000;
        #1;
        if (led !== 16'hcab5) begin
            $display("Simulation Failed: panel LED map mismatch value=%h", led);
            $finish;
        end
        if ((page !== 1'b0) || (an !== 8'hfe) || (seg !== 7'b0001000) || (dp !== 1'b0)) begin
            $display("Simulation Failed: panel PC page mismatch page=%b an=%h seg=%b dp=%b", page, an, seg, dp);
            $finish;
        end

        page_toggle = 1'b1;
        @(posedge clk);
        #1 page_toggle = 1'b0;
        #1;
        if ((page !== 1'b1) || (led !== 16'heab5) || (seg !== 7'b0001110) || (dp !== 1'b1)) begin
            $display("Simulation Failed: panel instruction page mismatch page=%b led=%h seg=%b dp=%b", page, led, seg, dp);
            $finish;
        end

        stage_sel = 3'd4;
        #1;
        if (seg !== 7'b0011001) begin
            $display("Simulation Failed: panel stage select mismatch seg=%b", seg);
            $finish;
        end

        release dut.scan_div_r;
        $display("Simulation succeeded: pipeline demo panel verified");
        $finish;
    end
endmodule
