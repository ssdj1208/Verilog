`timescale 1ns / 1ps

module bupt_riscv_tb();
    reg clk;
    reg rst;
    reg uart_rx_i;

    wire uart_tx_o;
    wire[15:0] led;
    wire bus_clk;
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
    wire acceptance_active;
    wire[15:0] acceptance_status;

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
    localparam integer TIMER_TICK_CYCLES = 50000;

    assign bus_clk = clk;

    integer cycle_count;
    reg[7:0] rx_byte;

    soc #(
        .UART_CLKS_PER_BIT(CLKS_PER_BIT),
        .TIMER_TICK_CYCLES(TIMER_TICK_CYCLES)
    ) dut(
        .clk(clk),
        .bus_clk(bus_clk),
        .rst(rst),
        .panel_switches_i(16'b0),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .led(led),
        .acceptance_active(acceptance_active),
        .acceptance_status(acceptance_status),
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

    ddr_model #(
        .ADDR_WIDTH(12),
        .CALIB_CYCLES(32),
        .READ_LATENCY(7),
        .WRITE_LATENCY(5)
    ) ddr_backend(
        .clk(clk),
        .rst(rst),
        .req_valid(ddr_backend_valid),
        .req_we(ddr_backend_we),
        .req_wstrb(ddr_backend_wstrb),
        .req_addr(ddr_backend_addr),
        .req_wdata(ddr_backend_wdata),
        .req_ready(ddr_backend_ready),
        .resp_valid(ddr_backend_resp_valid),
        .resp_rdata(ddr_backend_resp_rdata),
        .init_calib_complete(ddr_backend_calib_done),
        .busy(ddr_backend_busy)
        );

    initial begin
        clk <= 1'b0;
        forever #5 clk <= ~clk;
    end

    initial begin
        rst <= 1'b1;
        uart_rx_i <= 1'b1;
        cycle_count <= 0;
        #100;
        rst <= 1'b0;
    end

    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;
            if (cycle_count > 20000000) begin
                $display("Simulation Failed: timeout");
                $display("DEBUG pc=%h instr=%h instrD=%h pcD=%h pcE=%h validD=%b validE=%b",
                         dut.pc, dut.instr, dut.cpu.instrD, dut.cpu.pcD,
                         dut.cpu.pcE, dut.cpu.validD, dut.cpu.validE);
                $display("DEBUG memvalid=%b memready=%b memwrite=%b addr=%h wdata=%h rdata=%h",
                         dut.memvalid, dut.memready, dut.memwrite, dut.dataadr,
                         dut.writedata, dut.readdata);
                $display("DEBUG uart_tx_ready=%b uart_rx_valid=%b led=%h",
                         uart_tx_ready, uart_rx_valid, led);
                $finish;
            end
        end
    end

    task uart_recv_byte;
        output [7:0] data;
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
        input [7:0] data;
        begin
            uart_rx_i = 1'b1;
            #(BIT_NS * 8);
            uart_rx_i = 1'b0;
            #BIT_NS;
            uart_rx_i = data[0]; #BIT_NS;
            uart_rx_i = data[1]; #BIT_NS;
            uart_rx_i = data[2]; #BIT_NS;
            uart_rx_i = data[3]; #BIT_NS;
            uart_rx_i = data[4]; #BIT_NS;
            uart_rx_i = data[5]; #BIT_NS;
            uart_rx_i = data[6]; #BIT_NS;
            uart_rx_i = data[7]; #BIT_NS;
            uart_rx_i = 1'b1;
            #(BIT_NS * 2);
        end
    endtask

    task expect_byte;
        input [7:0] expected;
        integer extra_i;
        begin
            uart_recv_byte(rx_byte);
            if (rx_byte !== expected) begin
                $display("Simulation Failed: expected byte %h (%c), got %h (%c)",
                         expected, expected, rx_byte, rx_byte);
                $write("UART tail: %c", rx_byte);
                for (extra_i = 0; extra_i < 80; extra_i = extra_i + 1) begin
                    uart_recv_byte(rx_byte);
                    $write("%c", rx_byte);
                end
                $display("");
                $display("DEBUG pc=%h instr=%h instrD=%h pcD=%h pcE=%h validD=%b validE=%b",
                         dut.pc, dut.instr, dut.cpu.instrD, dut.cpu.pcD,
                         dut.cpu.pcE, dut.cpu.validD, dut.cpu.validE);
                $display("DEBUG cache accesses=%h hits=%h misses=%h replacements=%h",
                         dut.bus.cache_accesses, dut.bus.cache_hits,
                         dut.bus.cache_misses, dut.bus.cache_replacements);
                $finish;
            end
        end
    endtask

    task expect_string;
        input [8*128-1:0] text;
        integer i;
        integer len;
        reg[7:0] ch;
        begin
            len = 0;
            for (i = 127; i >= 0; i = i - 1) begin
                ch = text[i*8 +: 8];
                if (ch != 8'h00) begin
                    len = i + 1;
                    i = -1;
                end
            end
            for (i = len - 1; i >= 0; i = i - 1) begin
                expect_byte(text[i*8 +: 8]);
            end
        end
    endtask

    task send_string;
        input [8*32-1:0] text;
        integer i;
        integer len;
        reg[7:0] ch;
        begin
            len = 0;
            for (i = 31; i >= 0; i = i - 1) begin
                ch = text[i*8 +: 8];
                if (ch != 8'h00) begin
                    len = i + 1;
                    i = -1;
                end
            end
            for (i = len - 1; i >= 0; i = i - 1) begin
                uart_send_byte(text[i*8 +: 8]);
                #(BIT_NS * 300);
            end
        end
    endtask

    task expect_crlf;
        begin
            expect_byte(8'h0d);
            expect_byte(8'h0a);
        end
    endtask

    task expect_line;
        input [8*128-1:0] text;
        begin
            expect_string(text);
            expect_crlf();
        end
    endtask

    task send_line;
        input [8*32-1:0] text;
        begin
            send_string(text);
            uart_send_byte(8'h0d);
        end
    endtask

    task expect_hex_line;
        integer i;
        integer extra_i;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                uart_recv_byte(rx_byte);
                if (!((rx_byte >= "0" && rx_byte <= "9") ||
                      (rx_byte >= "A" && rx_byte <= "F"))) begin
                    $display("Simulation Failed: expected hex digit, got %h", rx_byte);
                    $write("UART tail: %c", rx_byte);
                    for (extra_i = 0; extra_i < 80; extra_i = extra_i + 1) begin
                        uart_recv_byte(rx_byte);
                        $write("%c", rx_byte);
                    end
                    $display("");
                    $finish;
                end
            end
            expect_crlf();
        end
    endtask

    task expect_nonzero_hex_line;
        integer i;
        integer extra_i;
        reg[31:0] value;
        begin
            value = 32'b0;
            for (i = 0; i < 8; i = i + 1) begin
                uart_recv_byte(rx_byte);
                value = {value[27:0], 4'b0};
                if (rx_byte >= "0" && rx_byte <= "9") begin
                    value[3:0] = rx_byte - "0";
                end else if (rx_byte >= "A" && rx_byte <= "F") begin
                    value[3:0] = rx_byte - "A" + 4'd10;
                end else begin
                    $display("Simulation Failed: expected hex digit, got %h", rx_byte);
                    $write("UART tail: %c", rx_byte);
                    for (extra_i = 0; extra_i < 80; extra_i = extra_i + 1) begin
                        uart_recv_byte(rx_byte);
                        $write("%c", rx_byte);
                    end
                    $display("");
                    $finish;
                end
            end
            expect_crlf();
            if (value == 32'b0) begin
                $display("Simulation Failed: expected nonzero hex value");
                $finish;
            end
        end
    endtask

    initial begin
        wait (rst == 1'b0);
        expect_line("BUPT RISC-V CPU PROJECT");
        expect_line("RV32I ISA PASS");
        expect_line("M EXT PASS");
        expect_line("DDR TEST OK");
        expect_line("CACHE READY");
        expect_line("FP TEST OK");
        expect_line("PERF READY");
        expect_string("rv32> ");

        send_line("help");
        expect_line("help accept accept clear mem perf perf clear bench alu bench mem bench branch cache fp led run int on off stat");
        expect_string("rv32> ");

        send_line("mem");
        expect_line("DDR TEST OK");
        expect_string("rv32> ");

        send_line("cache");
        expect_line("CACHE READY");
        expect_string("rv32> ");

        send_line("fp");
        expect_line("FP TEST OK");
        expect_string("rv32> ");

        send_line("led 1");
        expect_line("OK");
        expect_string("rv32> ");
        if (led[0] !== 1'b1) begin
            $display("Simulation Failed: led[0] expected 1 after led command, got %h", led);
            $finish;
        end

        send_line("run demo");
        expect_line("demo started");
        expect_string("rv32> ");

        send_line("perf");
        expect_string("cycles=");
        expect_hex_line();
        expect_string("retired=");
        expect_hex_line();
        expect_string("branches=");
        expect_hex_line();
        expect_string("mispredicts=");
        expect_hex_line();
        expect_string("stalls=");
        expect_hex_line();
        expect_string("stall_lu=");
        expect_hex_line();
        expect_string("stall_md=");
        expect_hex_line();
        expect_string("stall_dc=");
        expect_hex_line();
        expect_string("stall_if=");
        expect_hex_line();
        expect_string("stall_ddr=");
        expect_hex_line();
        expect_string("flush_br=");
        expect_hex_line();
        expect_string("flush_tr=");
        expect_hex_line();
        expect_string("forwards=");
        expect_hex_line();
        expect_string("rv32> ");

        send_line("perf clear");
        expect_line("OK");
        expect_string("rv32> ");

        send_line("perf");
        expect_string("cycles=");
        expect_hex_line();
        expect_string("retired=");
        expect_hex_line();
        expect_string("branches=");
        expect_hex_line();
        expect_string("mispredicts=");
        expect_hex_line();
        expect_string("stalls=");
        expect_hex_line();
        expect_string("stall_lu=");
        expect_hex_line();
        expect_string("stall_md=");
        expect_hex_line();
        expect_string("stall_dc=");
        expect_hex_line();
        expect_string("stall_if=");
        expect_hex_line();
        expect_string("stall_ddr=");
        expect_hex_line();
        expect_string("flush_br=");
        expect_hex_line();
        expect_string("flush_tr=");
        expect_hex_line();
        expect_string("forwards=");
        expect_hex_line();
        expect_string("rv32> ");

        send_line("bench alu");
        expect_string("BALU cycles=");
        expect_hex_line();
        expect_string("retired=");
        expect_hex_line();
        expect_string("branches=");
        expect_hex_line();
        expect_string("mispredicts=");
        expect_hex_line();
        expect_string("stalls=");
        expect_hex_line();
        expect_string("stall_lu=");
        expect_hex_line();
        expect_string("stall_md=");
        expect_hex_line();
        expect_string("stall_dc=");
        expect_hex_line();
        expect_string("stall_if=");
        expect_hex_line();
        expect_string("stall_ddr=");
        expect_hex_line();
        expect_string("flush_br=");
        expect_hex_line();
        expect_string("flush_tr=");
        expect_hex_line();
        expect_string("forwards=");
        expect_hex_line();
        expect_string("rv32> ");

        send_line("bench mem");
        expect_string("BMEM cycles=");
        expect_hex_line();
        expect_string("retired=");
        expect_hex_line();
        expect_string("branches=");
        expect_hex_line();
        expect_string("mispredicts=");
        expect_hex_line();
        expect_string("stalls=");
        expect_hex_line();
        expect_string("stall_lu=");
        expect_hex_line();
        expect_string("stall_md=");
        expect_hex_line();
        expect_string("stall_dc=");
        expect_hex_line();
        expect_string("stall_if=");
        expect_hex_line();
        expect_string("stall_ddr=");
        expect_hex_line();
        expect_string("flush_br=");
        expect_hex_line();
        expect_string("flush_tr=");
        expect_hex_line();
        expect_string("forwards=");
        expect_hex_line();
        expect_string("misses=");
        expect_hex_line();
        expect_string("rv32> ");

        send_line("bench branch");
        expect_string("BBR branches=");
        expect_hex_line();
        expect_string("mispredicts=");
        expect_hex_line();
        expect_string("cycles=");
        expect_hex_line();
        expect_string("retired=");
        expect_hex_line();
        expect_string("stalls=");
        expect_hex_line();
        expect_string("stall_lu=");
        expect_hex_line();
        expect_string("stall_md=");
        expect_hex_line();
        expect_string("stall_dc=");
        expect_hex_line();
        expect_string("stall_if=");
        expect_hex_line();
        expect_string("stall_ddr=");
        expect_hex_line();
        expect_string("flush_br=");
        expect_hex_line();
        expect_string("flush_tr=");
        expect_hex_line();
        expect_string("forwards=");
        expect_hex_line();
        expect_string("rv32> ");

        send_line("perf");
        expect_string("cycles=");
        expect_hex_line();
        expect_string("retired=");
        expect_hex_line();
        expect_string("branches=");
        expect_nonzero_hex_line();
        expect_string("mispredicts=");
        expect_hex_line();
        expect_string("stalls=");
        expect_hex_line();
        expect_string("stall_lu=");
        expect_hex_line();
        expect_string("stall_md=");
        expect_hex_line();
        expect_string("stall_dc=");
        expect_hex_line();
        expect_string("stall_if=");
        expect_hex_line();
        expect_string("stall_ddr=");
        expect_hex_line();
        expect_string("flush_br=");
        expect_hex_line();
        expect_string("flush_tr=");
        expect_hex_line();
        expect_string("forwards=");
        expect_hex_line();
        expect_string("rv32> ");

        // Interrupt test: enable timer interrupt. The handler toggles LED[1]
        // and increments a tick counter at BRAM 0x10400 each time it fires.
        send_line("int on");
        expect_line("INT ON");
        expect_string("rv32> ");

        begin : int_drain
            integer p;
            for (p = 0; p < 60; p = p + 1) begin
                send_line("t");
                expect_string("tick=");
                expect_hex_line();
                expect_string("pending=");
                expect_hex_line();
                expect_string("rv32> ");
            end
        end

        send_line("o");
        expect_line("INT OFF");
        expect_string("rv32> ");

        $display("Simulation succeeded: BUPT RISC-V CPU verified");
        $finish;
    end
endmodule
