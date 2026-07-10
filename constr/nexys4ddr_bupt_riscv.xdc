## Nexys4 DDR Rev. C constraints for BUPT RISC-V SoC

set_property BITSTREAM.STARTUP.STARTUPCLK JTAGCLK [current_design]

set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk100mhz }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk100mhz }]

## The DDR backend bridge uses explicit toggle synchronizers between the SoC
## bus clock and the MIG UI clock. Multi-bit payload registers are held stable
## until the synchronized toggle is acknowledged, so these crossings are CDC
## paths rather than single-cycle synchronous timing paths.
set_false_path -from [get_clocks -quiet soc_clk_100_unbuf] -to [get_clocks -quiet clk_pll_i]
set_false_path -from [get_clocks -quiet clk_pll_i] -to [get_clocks -quiet soc_clk_100_unbuf]

## FP MMIO exposes a software-polled ready bit and only publishes the result
## after the operands have been stable for three SoC clock cycles.
set fp_launch_regs [get_cells -quiet -hier -regexp {.*soc/bus/fp/(op_[ab]|op_sel)_reg\[[0-9]+\]}]
set fp_result_regs [get_cells -quiet -hier -regexp {.*soc/bus/fp/result_reg_reg\[[0-9]+\]}]
set fp_launch_pins [get_pins -quiet -of_objects $fp_launch_regs -filter {REF_PIN_NAME == C}]
set fp_capture_pins [get_pins -quiet -of_objects $fp_result_regs -filter {REF_PIN_NAME == D}]
set_multicycle_path 3 -setup -from $fp_launch_pins -to $fp_capture_pins
set_multicycle_path 2 -hold  -from $fp_launch_pins -to $fp_capture_pins

## Center button as reset
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { rst }]

## USB-UART through FT2232.  Digilent names these pins from the USB host
## perspective: UART_TXD_IN (C4) drives the FPGA RX input, and UART_RXD_OUT
## (D4) is driven by the FPGA TX output.  Verified on Nexys4 DDR hardware.
set_property -dict { PACKAGE_PIN C4 IOSTANDARD LVCMOS33 } [get_ports { uart_rx_i }]
set_property -dict { PACKAGE_PIN D4 IOSTANDARD LVCMOS33 } [get_ports { uart_tx_o }]

## LEDs
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { led[4] }]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { led[5] }]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { led[6] }]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports { led[7] }]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { led[8] }]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { led[9] }]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { led[10] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { led[11] }]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { led[12] }]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports { led[13] }]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { led[14] }]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports { led[15] }]
