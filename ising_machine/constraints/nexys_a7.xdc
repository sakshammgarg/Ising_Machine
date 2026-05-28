## =============================================================================
## Nexys A7 (Artix-7 XC7A100T-1CSG324C) Constraints for Ising Machine
## =============================================================================

## ----------------------------------------------------------------------------
## Clock (100 MHz onboard oscillator)
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports { clk }]

## ----------------------------------------------------------------------------
## Reset / Control Buttons (active high on Nexys A7)
## btnC = Center button → acts as start/reset in design
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { btnC }]

## Other buttons (unused but constrained to avoid DRC warnings)
# set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports { btnU }]
# set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports { btnL }]
# set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { btnR }]
# set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { btnD }]

## ----------------------------------------------------------------------------
## Switches SW[15:0]
## SW[1:0] → update mode (det/stoch/anneal)
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]

## ----------------------------------------------------------------------------
## LEDs LD[15:0] → spin[15:0] states
## ----------------------------------------------------------------------------
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

## ----------------------------------------------------------------------------
## UART (USB UART bridge via FT2232)
## uart_txd_in → FPGA TX → PC RX
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports { uart_txd_in }]

## ----------------------------------------------------------------------------
## VGA Connector
## ----------------------------------------------------------------------------
## Red channel
set_property -dict { PACKAGE_PIN A3  IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }]
set_property -dict { PACKAGE_PIN B4  IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }]
set_property -dict { PACKAGE_PIN C5  IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }]
set_property -dict { PACKAGE_PIN A4  IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }]

## Green channel
set_property -dict { PACKAGE_PIN C6  IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }]
set_property -dict { PACKAGE_PIN A5  IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }]
set_property -dict { PACKAGE_PIN B6  IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }]
set_property -dict { PACKAGE_PIN A6  IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }]

## Blue channel
set_property -dict { PACKAGE_PIN B7  IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }]
set_property -dict { PACKAGE_PIN C7  IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }]
set_property -dict { PACKAGE_PIN D7  IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }]
set_property -dict { PACKAGE_PIN D8  IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }]

## Sync signals
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { vga_hs }]
set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports { vga_vs }]

## ----------------------------------------------------------------------------
## Timing Constraints
## ----------------------------------------------------------------------------
## VGA pixel clock (derived from 100 MHz / 4 internally)
## Relax setup/hold on VGA outputs since they are presentation-only
set_output_delay -clock sys_clk_pin -max 0 [get_ports {vga_r[*] vga_g[*] vga_b[*] vga_hs vga_vs}]
set_output_delay -clock sys_clk_pin -min 0 [get_ports {vga_r[*] vga_g[*] vga_b[*] vga_hs vga_vs}]

## LED and UART outputs – relax timing (slow outputs)
set_output_delay -clock sys_clk_pin -max 0 [get_ports {led[*]}]
set_output_delay -clock sys_clk_pin -min 0 [get_ports {led[*]}]
set_output_delay -clock sys_clk_pin -max 0 [get_ports {uart_txd_in}]
set_output_delay -clock sys_clk_pin -min 0 [get_ports {uart_txd_in}]

## ----------------------------------------------------------------------------
## Bitstream Configuration
## ----------------------------------------------------------------------------
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLDOWN [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]