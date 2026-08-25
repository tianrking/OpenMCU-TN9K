`default_nettype none

// Customer-facing Tang Nano 9K MCU configuration.
//
// Its FPGA configuration contains the immutable OpenMCU bootloader only.
// Customer applications are subsequently written through UART0 into the
// separate GW1NR-9C User Flash and are never compiled into this bitstream.
`ifdef OMCU_ROM_IMAGE_BUILD
`include "omcu_rom_image_config.vh"
`endif

module omcu_tn9k_mcu_top #(
`ifdef OMCU_ROM_IMAGE_BUILD
  parameter ROM_INIT_FILE = `OMCU_ROM_IMAGE_FILE,
`else
  parameter ROM_INIT_FILE = "rtl/platform/tangnano9k/firmware/bootloader.hex",
`endif
  parameter integer ROM_WORDS = 2048,
  parameter integer SRAM_BYTES = 45056
) (
  input  logic       clk_27m_i,
  input  logic       resetn_i,
  input  logic       uart_rx_i,
  output logic       uart_tx_o,
  output logic [5:0] led_n_o,
  input  logic       spi0_miso_i,
  output logic       spi0_mosi_o,
  output logic       spi0_sck_o,
  output logic       spi0_cs_n_o,
  inout  wire        i2c0_scl_io,
  inout  wire        i2c0_sda_io,
  output logic       pwm0_o,
  inout  wire [11:0] gpio_io
);

  omcu_tn9k_bringup_top #(
    .ROM_INIT_FILE(ROM_INIT_FILE),
    .ROM_WORDS(ROM_WORDS),
    .SRAM_BYTES(SRAM_BYTES),
    .USER_FLASH_BYTES(77824),
    .USER_FLASH_PRESENT(1),
    .USER_FLASH_USE_GOWIN_PRIMITIVE(1),
    .APPLICATION_BOOT_MODE(1)
  ) platform (
    .clk_27m_i(clk_27m_i),
    .resetn_i(resetn_i),
    .uart_rx_i(uart_rx_i),
    .uart_tx_o(uart_tx_o),
    .led_n_o(led_n_o),
    .spi0_miso_i(spi0_miso_i),
    .spi0_mosi_o(spi0_mosi_o),
    .spi0_sck_o(spi0_sck_o),
    .spi0_cs_n_o(spi0_cs_n_o),
    .i2c0_scl_io(i2c0_scl_io),
    .i2c0_sda_io(i2c0_sda_io),
    .pwm0_o(pwm0_o),
    .gpio_io(gpio_io)
  );

endmodule

`default_nettype wire
