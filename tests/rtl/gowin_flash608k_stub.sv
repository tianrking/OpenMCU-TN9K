`default_nettype none

// Simulation-only shape check for the documented GW1NR FLASH608K primitive.
// It intentionally models an erased device because the product-top smoke test
// verifies integration/elaboration, while omcu_user_flash_tb owns transaction
// behavior. Never include this file in a Gowin FPGA build.
module FLASH608K (
  output wire [31:0] DOUT,
  input  wire        XE,
  input  wire        YE,
  input  wire        SE,
  input  wire        PROG,
  input  wire        ERASE,
  input  wire        NVSTR,
  input  wire [8:0]  XADR,
  input  wire [5:0]  YADR,
  input  wire [31:0] DIN
);
  assign DOUT = 32'h0000_0000;
endmodule

`default_nettype wire
