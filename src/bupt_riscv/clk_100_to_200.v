`timescale 1ns / 1ps

module clk_100_to_200(
    input wire clk100,
    input wire rst,
    output wire clk200,
    output wire clk50,
    output wire clk50_180,
    output wire locked
    );

    wire clkfb;
    wire clkfb_buf;
    wire clk200_unbuf;
    wire clk50_unbuf;
    wire clk50_180_unbuf;

    BUFG clkfb_bufg(
        .I(clkfb),
        .O(clkfb_buf)
        );

    BUFG clk200_bufg(
        .I(clk200_unbuf),
        .O(clk200)
        );

    BUFG clk50_bufg(
        .I(clk50_unbuf),
        .O(clk50)
        );

    BUFG clk50_180_bufg(
        .I(clk50_180_unbuf),
        .O(clk50_180)
        );

    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.000),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.000),
        .CLKFBOUT_PHASE(0.000),
        .CLKOUT0_DIVIDE_F(5.000),
        .CLKOUT0_PHASE(0.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT1_DIVIDE(20),
        .CLKOUT1_PHASE(0.000),
        .CLKOUT1_DUTY_CYCLE(0.500),
        .CLKOUT2_DIVIDE(20),
        .CLKOUT2_PHASE(180.000),
        .CLKOUT2_DUTY_CYCLE(0.500),
        .STARTUP_WAIT("FALSE")
    ) mmcm(
        .CLKIN1(clk100),
        .CLKFBIN(clkfb_buf),
        .RST(rst),
        .PWRDWN(1'b0),
        .CLKFBOUT(clkfb),
        .CLKFBOUTB(),
        .CLKOUT0(clk200_unbuf),
        .CLKOUT0B(),
        .CLKOUT1(clk50_unbuf),
        .CLKOUT1B(),
        .CLKOUT2(clk50_180_unbuf),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(locked)
        );
endmodule
