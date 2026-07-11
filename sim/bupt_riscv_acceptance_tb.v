`timescale 1ns / 1ps

module bupt_riscv_acceptance_tb();
    reg clk;
    reg rst;
    reg uart_rx_i;
    wire uart_tx_o;
    wire[15:0] led;
    wire acceptance_active;
    wire[15:0] acceptance_status;
    wire[31:0] acceptance_display_value;

    wire ddr_backend_valid;
    wire ddr_backend_we;
    wire[3:0] ddr_backend_wstrb;
    wire[26:0] ddr_backend_addr;
    wire[31:0] ddr_backend_wdata;
    wire ddr_backend_ready;
    wire ddr_backend_resp_valid;
    wire[31:0] ddr_backend_resp_rdata;
    wire ddr_backend_calib_done;
    wire ddr_backend_busy;

    localparam integer CLKS_PER_BIT = 16;
    localparam integer BIT_NS = CLKS_PER_BIT * 10;
    integer cycle_count;
    integer phase;
    reg[7:0] rx_byte;

    soc #(
        .UART_CLKS_PER_BIT(CLKS_PER_BIT),
        .TIMER_TICK_CYCLES(32'd50000)
    ) dut(
        .clk(clk),
        .bus_clk(clk),
        .rst(rst),
        .panel_switches_i(16'b0),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .led(led),
        .acceptance_active(acceptance_active),
        .acceptance_status(acceptance_status),
        .acceptance_display_value(acceptance_display_value),
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
        .debug_writedata(),
        .debug_dataadr(),
        .debug_memwrite(),
        .uart_tx_ready(),
        .uart_rx_valid(),
        .demo_pcF(), .demo_pcD(), .demo_pcE(), .demo_pcM(), .demo_pcW(),
        .demo_instrF(), .demo_instrD(), .demo_instrE(), .demo_instrM(), .demo_instrW(),
        .demo_validF(), .demo_validD(), .demo_validE(), .demo_validM(), .demo_validW(),
        .demo_stallF(), .demo_stallD(), .demo_stall_loaduse(),
        .demo_stall_muldiv(), .demo_stall_dcache(), .demo_stall_ifetch(),
        .demo_flush_branch(), .demo_flush_trap()
        );

    ddr_model #(
        .ADDR_WIDTH(12),
        .CALIB_CYCLES(32),
        .READ_LATENCY(7),
        .WRITE_LATENCY(5)
    ) ddr_backend(
        .clk(clk), .rst(rst), .req_valid(ddr_backend_valid),
        .req_we(ddr_backend_we), .req_wstrb(ddr_backend_wstrb),
        .req_addr(ddr_backend_addr), .req_wdata(ddr_backend_wdata),
        .req_ready(ddr_backend_ready), .resp_valid(ddr_backend_resp_valid),
        .resp_rdata(ddr_backend_resp_rdata),
        .init_calib_complete(ddr_backend_calib_done), .busy(ddr_backend_busy)
        );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;
            if (cycle_count > 12000000) begin
                $display("Simulation Failed: acceptance UART timeout pc=%h status=%h", dut.pc, acceptance_status);
                $finish;
            end
        end
    end

    task uart_recv_byte;
        output[7:0] data;
        integer bit_i;
        begin
            @(negedge uart_tx_o);
            #(BIT_NS + (BIT_NS / 2));
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                data[bit_i] = uart_tx_o;
                #BIT_NS;
            end
            #(BIT_NS / 2);
        end
    endtask

    task uart_send_byte;
        input[7:0] data;
        begin
            uart_rx_i = 1'b0; #BIT_NS;
            uart_rx_i = data[0]; #BIT_NS;
            uart_rx_i = data[1]; #BIT_NS;
            uart_rx_i = data[2]; #BIT_NS;
            uart_rx_i = data[3]; #BIT_NS;
            uart_rx_i = data[4]; #BIT_NS;
            uart_rx_i = data[5]; #BIT_NS;
            uart_rx_i = data[6]; #BIT_NS;
            uart_rx_i = data[7]; #BIT_NS;
            uart_rx_i = 1'b1; #(BIT_NS * 2);
        end
    endtask

    task expect_string;
        input[8*64-1:0] text;
        integer i;
        integer len;
        reg[7:0] ch;
        begin
            len = 0;
            for (i = 63; i >= 0; i = i - 1) begin
                ch = text[i*8 +: 8];
                if (ch != 0) begin len = i + 1; i = -1; end
            end
            for (i = len - 1; i >= 0; i = i - 1) begin
                uart_recv_byte(rx_byte);
                if (rx_byte != text[i*8 +: 8]) begin
                    $display("Simulation Failed: acceptance UART phase=%0d expected %h got %h", phase, text[i*8 +: 8], rx_byte);
                    $finish;
                end
            end
        end
    endtask

    task expect_line;
        input[8*64-1:0] text;
        begin
            expect_string(text);
            uart_recv_byte(rx_byte);
            if (rx_byte != 8'h0d) begin
                $display("Simulation Failed: acceptance UART phase=%0d expected CR got %h", phase, rx_byte);
                $finish;
            end
            uart_recv_byte(rx_byte);
            if (rx_byte != 8'h0a) begin
                $display("Simulation Failed: acceptance UART phase=%0d expected LF got %h", phase, rx_byte);
                $finish;
            end
        end
    endtask

    task send_line;
        input[8*32-1:0] text;
        integer i;
        integer len;
        reg[7:0] ch;
        begin
            len = 0;
            for (i = 31; i >= 0; i = i - 1) begin
                ch = text[i*8 +: 8];
                if (ch != 0) begin len = i + 1; i = -1; end
            end
            for (i = len - 1; i >= 0; i = i - 1) begin
                uart_send_byte(text[i*8 +: 8]);
                #(BIT_NS * 300);
            end
            uart_send_byte(8'h0d);
        end
    endtask

    task expect_until;
        input[8*64-1:0] text;
        integer i;
        integer len;
        integer matched;
        reg[7:0] ch;
        reg[7:0] expected_ch;
        begin
            len = 0;
            for (i = 63; i >= 0; i = i - 1) begin
                ch = text[i*8 +: 8];
                if (ch != 0) begin len = i + 1; i = -1; end
            end
            matched = 0;
            while (matched < len) begin
                uart_recv_byte(rx_byte);
                expected_ch = text[(len - 1 - matched)*8 +: 8];
                if (rx_byte == expected_ch) matched = matched + 1;
                else matched = 0;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        uart_rx_i = 1'b1;
        cycle_count = 0;
        phase = 0;
        #100 rst = 1'b0;

        phase = 1;
        expect_line("BUPT RISC-V CPU PROJECT");
        phase = 2;
        expect_line("RV32I ISA PASS");
        phase = 3;
        expect_line("M EXT PASS");
        phase = 4;
        expect_line("DDR TEST OK");
        phase = 5;
        expect_line("CACHE READY");
        phase = 6;
        expect_line("FP TEST OK");
        phase = 7;
        expect_line("PERF READY");
        phase = 8;
        expect_string("rv32> ");

        phase = 9;
        send_line("accept");
        expect_until("ACCEPT_STATUS=FFFF");
        expect_line("");
        expect_line("ACCEPTANCE PASS");
        expect_string("rv32> ");
        if (!acceptance_active || acceptance_status != 16'hffff ||
            acceptance_display_value != 32'hacce5500) begin
            $display("Simulation Failed: acceptance result active=%b status=%h display=%h",
                     acceptance_active, acceptance_status, acceptance_display_value);
            $finish;
        end
        if (dut.bus.acceptance.display_value_r[10] < 32'h00009900) begin
            $display("Simulation Failed: I-Cache hit-rate display is not near 100%%: %h",
                     dut.bus.acceptance.display_value_r[10]);
            $finish;
        end

        phase = 10;
        send_line("accept clear");
        expect_line("OK");
        expect_string("rv32> ");
        if (acceptance_active) begin
            $display("Simulation Failed: acceptance clear did not deactivate panel");
            $finish;
        end

        $display("Simulation succeeded: enhanced acceptance UART verified");
        $finish;
    end
endmodule
