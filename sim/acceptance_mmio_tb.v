`timescale 1ns / 1ps

module acceptance_mmio_tb();
    reg clk;
    reg rst;
    reg we;
    reg re;
    reg[7:0] addr;
    reg[31:0] wdata;
    reg[3:0] display_sel;
    wire[31:0] rdata;
    wire active;
    wire[15:0] status;
    wire[15:0] fail;
    wire[31:0] live_result;
    wire[31:0] display_value;
    wire[7:0] display_dp;

    acceptance_mmio dut(
        .clk(clk),
        .rst(rst),
        .we(we),
        .re(re),
        .addr(addr),
        .wdata(wdata),
        .display_sel_i(display_sel),
        .rdata(rdata),
        .active_o(active),
        .status_o(status),
        .fail_o(fail),
        .live_result_o(live_result),
        .display_value_o(display_value),
        .display_dp_o(display_dp)
        );

    always #5 clk = ~clk;

    task write_reg;
        input[7:0] write_addr;
        input[31:0] write_data;
        begin
            @(negedge clk);
            addr = write_addr;
            wdata = write_data;
            we = 1'b1;
            @(negedge clk);
            we = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        we = 1'b0;
        re = 1'b0;
        addr = 8'b0;
        wdata = 32'b0;
        display_sel = 4'd2;
        #20 rst = 1'b0;

        write_reg(8'h00, 32'h00000007);
        write_reg(8'h04, 32'h0000a55a);
        write_reg(8'h08, 32'h12345678);
        write_reg(8'h0c, 32'h00000020);
        write_reg(8'h48, 32'h00001234);
        write_reg(8'h88, 32'h00000008);

        #1;
        if (!active || status != 16'ha55a || fail != 16'h0020 ||
            live_result != 32'h12345678 || display_value != 32'h00001234 ||
            display_dp != 8'h08) begin
            $display("Simulation Failed: acceptance MMIO output mismatch");
            $finish;
        end

        addr = 8'h48;
        #1;
        if (rdata != 32'h00001234) begin
            $display("Simulation Failed: acceptance MMIO readback mismatch");
            $finish;
        end

        rst = 1'b1;
        #11;
        if (active || status != 16'b0 || display_value != 32'b0) begin
            $display("Simulation Failed: acceptance MMIO reset mismatch");
            $finish;
        end

        $display("Simulation succeeded: acceptance MMIO verified");
        $finish;
    end
endmodule
