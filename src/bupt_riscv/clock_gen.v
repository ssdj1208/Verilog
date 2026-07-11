`timescale 1ns / 1ps

// 板级时钟生成模块。
// 通过 Vivado 时钟 IP 将 100 MHz 输入时钟转换为 SoC 时钟和 DDR/MIG 所需时钟，
// locked 表示内部 MMCM/PLL 已完成锁定，系统通常在该信号有效后再释放复位。
module clock_gen(
    input wire clk100,
    input wire rst,
    output wire mig_sys_clk_200mhz,
    output wire soc_clk_100mhz,
    output wire locked
    );

    wire clkfb;
    wire clkfb_buf;
    wire mig_sys_clk_200_unbuf;
    wire soc_clk_100_unbuf;

    BUFG clkfb_bufg(
        .I(clkfb),
        .O(clkfb_buf)
        );

    BUFG mig_sys_clk_200_bufg(
        .I(mig_sys_clk_200_unbuf),
        .O(mig_sys_clk_200mhz)
        );

    BUFG soc_clk_100_bufg(
        .I(soc_clk_100_unbuf),
        .O(soc_clk_100mhz)
        );

    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.000),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.000),
        .CLKFBOUT_PHASE(0.000),
        .CLKOUT0_DIVIDE_F(5.000),
        .CLKOUT0_PHASE(0.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT1_DIVIDE(10),  // 1000/10 = 100 MHz SoC/bus clock
        .CLKOUT1_PHASE(0.000),
        .CLKOUT1_DUTY_CYCLE(0.500),
        .STARTUP_WAIT("FALSE")
    ) mmcm(
        .CLKIN1(clk100),
        .CLKFBIN(clkfb_buf),
        .RST(rst),
        .PWRDWN(1'b0),
        .CLKFBOUT(clkfb),
        .CLKFBOUTB(),
        .CLKOUT0(mig_sys_clk_200_unbuf),
        .CLKOUT0B(),
        .CLKOUT1(soc_clk_100_unbuf),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(locked)
        );
endmodule
