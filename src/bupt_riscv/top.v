`timescale 1ns / 1ps

module top(
    input wire clk100mhz,
    input wire[4:0] btn,
    input wire[15:0] sw,
    input wire uart_rx_i,
    output wire uart_tx_o,
    output wire[15:0] led,
    output wire[7:0] an,
    output wire[6:0] seg,
    output wire dp,

    inout wire[15:0] ddr2_dq,
    inout wire[1:0] ddr2_dqs_n,
    inout wire[1:0] ddr2_dqs_p,
    output wire[12:0] ddr2_addr,
    output wire[2:0] ddr2_ba,
    output wire ddr2_ras_n,
    output wire ddr2_cas_n,
    output wire ddr2_we_n,
    output wire[0:0] ddr2_ck_p,
    output wire[0:0] ddr2_ck_n,
    output wire[0:0] ddr2_cke,
    output wire[0:0] ddr2_cs_n,
    output wire[1:0] ddr2_dm,
    output wire[0:0] ddr2_odt
    );

    localparam BTN_U = 0;
    localparam BTN_L = 1;
    localparam BTN_C = 2;
    localparam BTN_R = 3;
    localparam BTN_D = 4;

    wire rst_btn = btn[BTN_C];

    // Hold MIG in reset for a short time after FPGA configuration. This keeps
    // the board-level reset behavior deterministic before DDR calibration starts.
    reg[19:0] por_count = 20'd0;
    reg por_rst = 1'b1;
    reg demo_mode_latched = 1'b0;

    always @(posedge clk100mhz or posedge rst_btn) begin
        if (rst_btn) begin
            por_count <= 20'd0;
            por_rst <= 1'b1;
            demo_mode_latched <= sw[15];
        end else if (por_count != 20'hfffff) begin
            por_count <= por_count + 1'b1;
            por_rst <= 1'b1;
            demo_mode_latched <= sw[15];
        end else begin
            por_rst <= 1'b0;
        end
    end

    wire clk200mhz;
    wire clk50mhz;
    wire clk50mhz_180;
    wire clk200_locked;

    clk_100_to_200 clkgen(
        .clk100(clk100mhz),
        .rst(rst_btn),
        .clk200(clk200mhz),
        .clk50(clk50mhz),
        .clk50_180(clk50mhz_180),
        .locked(clk200_locked)
        );

    wire run_btn_level;
    wire run_btn_pulse;
    wire step_btn_level;
    wire step_btn_pulse;
    wire page_btn_level;
    wire page_btn_pulse;
    wire speed_btn_level;
    wire speed_btn_pulse;

    button_edge run_btn(
        .clk(clk50mhz),
        .rst(por_rst),
        .raw_i(btn[BTN_U]),
        .level_o(run_btn_level),
        .pressed_o(run_btn_pulse)
        );

    button_edge step_btn(
        .clk(clk50mhz),
        .rst(por_rst),
        .raw_i(btn[BTN_L]),
        .level_o(step_btn_level),
        .pressed_o(step_btn_pulse)
        );

    button_edge page_btn(
        .clk(clk50mhz),
        .rst(por_rst),
        .raw_i(btn[BTN_R]),
        .level_o(page_btn_level),
        .pressed_o(page_btn_pulse)
        );

    button_edge speed_btn(
        .clk(clk50mhz),
        .rst(por_rst),
        .raw_i(btn[BTN_D]),
        .level_o(speed_btn_level),
        .pressed_o(speed_btn_pulse)
        );

    wire ui_clk;
    wire ui_clk_sync_rst;
    wire ui_addn_clk_0;
    wire ui_addn_clk_1;
    wire ui_addn_clk_2;
    wire ui_addn_clk_3;
    wire ui_addn_clk_4;
    wire mig_mmcm_locked;
    wire mig_aresetn;
    wire init_calib_complete;
    wire app_sr_active;
    wire app_ref_ack;
    wire app_zq_ack;

    wire[0:0] s_axi_awid;
    wire[26:0] s_axi_awaddr;
    wire[7:0] s_axi_awlen;
    wire[2:0] s_axi_awsize;
    wire[1:0] s_axi_awburst;
    wire[0:0] s_axi_awlock;
    wire[3:0] s_axi_awcache;
    wire[2:0] s_axi_awprot;
    wire[3:0] s_axi_awqos;
    wire s_axi_awvalid;
    wire s_axi_awready;
    wire[63:0] s_axi_wdata;
    wire[7:0] s_axi_wstrb;
    wire s_axi_wlast;
    wire s_axi_wvalid;
    wire s_axi_wready;
    wire[0:0] s_axi_bid;
    wire[1:0] s_axi_bresp;
    wire s_axi_bvalid;
    wire s_axi_bready;
    wire[0:0] s_axi_arid;
    wire[26:0] s_axi_araddr;
    wire[7:0] s_axi_arlen;
    wire[2:0] s_axi_arsize;
    wire[1:0] s_axi_arburst;
    wire[0:0] s_axi_arlock;
    wire[3:0] s_axi_arcache;
    wire[2:0] s_axi_arprot;
    wire[3:0] s_axi_arqos;
    wire s_axi_arvalid;
    wire s_axi_arready;
    wire[0:0] s_axi_rid;
    wire[63:0] s_axi_rdata;
    wire[1:0] s_axi_rresp;
    wire s_axi_rlast;
    wire s_axi_rvalid;
    wire s_axi_rready;

    reg[3:0] rst_sync;
    wire soc_rst;
    wire soc_clk;
    wire bus_clk;
    wire backend_clk = ui_clk;
    wire demo_run_active;
    wire demo_speed_sel;

    demo_clock_ctrl demo_clk_ctrl(
        .clk_i(clk50mhz),
        .rst_i(por_rst),
        .demo_mode_i(demo_mode_latched),
        .run_toggle_i(run_btn_pulse),
        .step_i(step_btn_pulse),
        .speed_toggle_i(speed_btn_pulse),
        .soc_clk_o(soc_clk),
        .run_active_o(demo_run_active),
        .speed_sel_o(demo_speed_sel)
        );

    assign bus_clk = soc_clk;

    always @(posedge soc_clk or posedge por_rst) begin
        if (por_rst) begin
            rst_sync <= 4'hf;
        end else begin
            rst_sync <= {rst_sync[2:0], 1'b0};
        end
    end

    assign soc_rst = rst_sync[3];
    assign mig_aresetn = ~ui_clk_sync_rst;

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
    wire axi_backend_valid;
    wire axi_backend_we;
    wire[3:0] axi_backend_wstrb;
    wire[26:0] axi_backend_addr;
    wire[31:0] axi_backend_wdata;
    wire axi_backend_ready;
    wire axi_backend_resp_valid;
    wire[31:0] axi_backend_resp_rdata;
    wire axi_backend_busy;

    wire[31:0] debug_writedata;
    wire[31:0] debug_dataadr;
    wire debug_memwrite;
    wire uart_tx_ready;
    wire uart_rx_valid;
    wire[15:0] soc_led;
    wire[15:0] demo_led;
    wire[7:0] demo_an;
    wire[6:0] demo_seg;
    wire demo_dp;
    wire[31:0] demo_pcF;
    wire[31:0] demo_pcD;
    wire[31:0] demo_pcE;
    wire[31:0] demo_pcM;
    wire[31:0] demo_pcW;
    wire[31:0] demo_instrF;
    wire[31:0] demo_instrD;
    wire[31:0] demo_instrE;
    wire[31:0] demo_instrM;
    wire[31:0] demo_instrW;
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

    soc #(
        .UART_CLKS_PER_BIT(868),
        .TIMER_TICK_CYCLES(32'd1000000)
    ) soc(
        .clk(soc_clk),
        .bus_clk(bus_clk),
        .rst(soc_rst),
        .panel_switches_i(sw),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .led(soc_led),
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
        .demo_stall_loaduse(demo_stall_loaduse),
        .demo_stall_muldiv(demo_stall_muldiv),
        .demo_stall_dcache(demo_stall_dcache),
        .demo_stall_ifetch(demo_stall_ifetch),
        .demo_flush_branch(demo_flush_branch),
        .demo_flush_trap(demo_flush_trap)
        );

    pipeline_demo_panel demo_panel(
        .clk(clk50mhz),
        .rst(por_rst),
        .demo_mode_i(demo_mode_latched),
        .page_toggle_i(page_btn_pulse),
        .stage_sel_i(sw[2:0]),
        .run_active_i(demo_run_active),
        .speed_sel_i(demo_speed_sel),
        .pcF_i(demo_pcF),
        .pcD_i(demo_pcD),
        .pcE_i(demo_pcE),
        .pcM_i(demo_pcM),
        .pcW_i(demo_pcW),
        .instrF_i(demo_instrF),
        .instrD_i(demo_instrD),
        .instrE_i(demo_instrE),
        .instrM_i(demo_instrM),
        .instrW_i(demo_instrW),
        .validF_i(demo_validF),
        .validD_i(demo_validD),
        .validE_i(demo_validE),
        .validM_i(demo_validM),
        .validW_i(demo_validW),
        .stall_loaduse_i(demo_stall_loaduse),
        .stall_muldiv_i(demo_stall_muldiv),
        .stall_ifetch_i(demo_stall_ifetch),
        .stall_dcache_i(demo_stall_dcache),
        .flush_branch_i(demo_flush_branch),
        .flush_trap_i(demo_flush_trap),
        .led_o(demo_led),
        .an_o(demo_an),
        .seg_o(demo_seg),
        .dp_o(demo_dp),
        .page_o()
        );

    assign led = demo_mode_latched ? demo_led : soc_led;
    assign an = demo_mode_latched ? demo_an : 8'hff;
    assign seg = demo_mode_latched ? demo_seg : 7'h7f;
    assign dp = demo_mode_latched ? demo_dp : 1'b1;

    ddr_backend_cdc ddr_cdc(
        .bus_clk(bus_clk),
        .bus_rst(soc_rst),
        .bus_valid(ddr_backend_valid),
        .bus_we(ddr_backend_we),
        .bus_wstrb(ddr_backend_wstrb),
        .bus_addr(ddr_backend_addr),
        .bus_wdata(ddr_backend_wdata),
        .bus_ready(ddr_backend_ready),
        .bus_resp_valid(ddr_backend_resp_valid),
        .bus_resp_rdata(ddr_backend_resp_rdata),
        .bus_calib_done(ddr_backend_calib_done),
        .bus_busy(ddr_backend_busy),
        .axi_clk(backend_clk),
        .axi_rst(ui_clk_sync_rst),
        .axi_valid(axi_backend_valid),
        .axi_we(axi_backend_we),
        .axi_wstrb(axi_backend_wstrb),
        .axi_addr(axi_backend_addr),
        .axi_wdata(axi_backend_wdata),
        .axi_ready(axi_backend_ready),
        .axi_resp_valid(axi_backend_resp_valid),
        .axi_resp_rdata(axi_backend_resp_rdata),
        .axi_calib_done(init_calib_complete),
        .axi_busy(axi_backend_busy)
        );

    mig_axi_adapter ddr_axi(
        .clk(backend_clk),
        .rst(ui_clk_sync_rst),
        .backend_valid(axi_backend_valid),
        .backend_we(axi_backend_we),
        .backend_wstrb(axi_backend_wstrb),
        .backend_addr(axi_backend_addr),
        .backend_wdata(axi_backend_wdata),
        .backend_ready(axi_backend_ready),
        .backend_resp_valid(axi_backend_resp_valid),
        .backend_resp_rdata(axi_backend_resp_rdata),
        .init_calib_complete(init_calib_complete),
        .busy(axi_backend_busy),
        .s_axi_awid(s_axi_awid),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst),
        .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awqos(s_axi_awqos),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst),
        .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arqos(s_axi_arqos),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready)
        );

    lab10_mig u_lab10_mig(
        .ddr2_addr(ddr2_addr),
        .ddr2_ba(ddr2_ba),
        .ddr2_cas_n(ddr2_cas_n),
        .ddr2_ck_n(ddr2_ck_n),
        .ddr2_ck_p(ddr2_ck_p),
        .ddr2_cke(ddr2_cke),
        .ddr2_ras_n(ddr2_ras_n),
        .ddr2_we_n(ddr2_we_n),
        .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n),
        .ddr2_dqs_p(ddr2_dqs_p),
        .init_calib_complete(init_calib_complete),
        .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt),
        .ui_clk(ui_clk),
        .ui_clk_sync_rst(ui_clk_sync_rst),
        .ui_addn_clk_0(ui_addn_clk_0),
        .ui_addn_clk_1(ui_addn_clk_1),
        .ui_addn_clk_2(ui_addn_clk_2),
        .ui_addn_clk_3(ui_addn_clk_3),
        .ui_addn_clk_4(ui_addn_clk_4),
        .mmcm_locked(mig_mmcm_locked),
        .aresetn(mig_aresetn),
        .app_sr_req(1'b0),
        .app_ref_req(1'b0),
        .app_zq_req(1'b0),
        .app_sr_active(app_sr_active),
        .app_ref_ack(app_ref_ack),
        .app_zq_ack(app_zq_ack),
        .s_axi_awid(s_axi_awid),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst),
        .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awqos(s_axi_awqos),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst),
        .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arqos(s_axi_arqos),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .sys_clk_i(clk200mhz),
        .sys_rst(~por_rst & clk200_locked)
        );
endmodule
