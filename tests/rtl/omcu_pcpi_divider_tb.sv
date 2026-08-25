`default_nettype none
`timescale 1ns / 1ps

module omcu_pcpi_divider_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic valid;
  logic [31:0] insn;
  logic [31:0] rs1;
  logic [31:0] rs2;
  logic wr;
  logic [31:0] rd;
  logic wait_req;
  logic ready;

  always #5 clk = ~clk;

  omcu_pcpi_divider dut (
    .clk_i(clk), .rst_ni(rst_n), .pcpi_valid_i(valid), .pcpi_insn_i(insn),
    .pcpi_rs1_i(rs1), .pcpi_rs2_i(rs2), .pcpi_wr_o(wr), .pcpi_rd_o(rd),
    .pcpi_wait_o(wait_req), .pcpi_ready_o(ready)
  );

  function automatic logic [31:0] div_insn(input logic [2:0] funct3);
    div_insn = {7'b0000001, 5'd0, 5'd0, funct3, 5'd0, 7'b0110011};
  endfunction

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $error("%s", message);
        $fatal(1);
      end
    end
  endtask

  task automatic execute(
    input logic [2:0] funct3,
    input logic [31:0] left,
    input logic [31:0] right,
    input logic [31:0] expected,
    input string message
  );
    integer cycles;
    begin
      @(negedge clk);
      valid = 1'b1;
      insn = div_insn(funct3);
      rs1 = left;
      rs2 = right;
      #1 check(wait_req, "recognized divide instruction must claim PCPI immediately");
      cycles = 0;
      while (!ready && cycles < 40) begin
        @(negedge clk);
        cycles = cycles + 1;
      end
      check(ready && wr, "divide operation must produce one PCPI write response");
      check(rd == expected, message);
      @(negedge clk);
      valid = 1'b0;
      insn = '0;
      rs1 = '0;
      rs2 = '0;
      @(negedge clk);
    end
  endtask

  initial begin
    valid = 1'b0;
    insn = '0;
    rs1 = '0;
    rs2 = '0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    execute(3'b100, -32'sd10, 32'd3, -32'sd3, "DIV must truncate signed quotient toward zero");
    execute(3'b110, -32'sd10, 32'd3, -32'sd1, "REM must retain signed dividend remainder");
    execute(3'b101, 32'hffff_fffe, 32'd3, 32'h5555_5554, "DIVU must be unsigned");
    execute(3'b111, 32'hffff_fffe, 32'd3, 32'd2, "REMU must be unsigned");
    execute(3'b100, 32'h8000_0000, 32'hffff_ffff, 32'h8000_0000,
            "DIV signed overflow result must follow RV32M");
    execute(3'b110, 32'h8000_0000, 32'hffff_ffff, 32'h0000_0000,
            "REM signed overflow result must be zero");
    execute(3'b100, 32'h1234_5678, 32'h0000_0000, 32'hffff_ffff,
            "DIV by zero must return all ones");
    execute(3'b111, 32'h1234_5678, 32'h0000_0000, 32'h1234_5678,
            "REMU by zero must return the dividend");

    $display("PASS: omcu_pcpi_divider_tb");
    $finish;
  end
endmodule

`default_nettype wire
