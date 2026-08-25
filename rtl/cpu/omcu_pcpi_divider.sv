`ifndef OMCU_PCPI_DIVIDER_INCLUDED
`define OMCU_PCPI_DIVIDER_INCLUDED
`default_nettype none

// Compact RV32M DIV/DIVU/REM/REMU PCPI coprocessor.  It uses one restoring
// division step per clock (32 steps for a normal operation) and deliberately
// keeps only a 33-bit remainder instead of PicoRV32's larger shifted-divisor
// datapath.  That resource trade is what makes the complete Tang Nano 9K P1
// peripheral profile physically routable while preserving the RV32IMC ISA.
module omcu_pcpi_divider (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        pcpi_valid_i,
  input  logic [31:0] pcpi_insn_i,
  input  logic [31:0] pcpi_rs1_i,
  input  logic [31:0] pcpi_rs2_i,
  output logic        pcpi_wr_o,
  output logic [31:0] pcpi_rd_o,
  output logic        pcpi_wait_o,
  output logic        pcpi_ready_o
);

  logic instr_div;
  logic instr_divu;
  logic instr_rem;
  logic instr_remu;
  logic instr_any;
  logic instr_signed;
  logic instr_quotient;

  logic        running_q;
  logic        completed_q;
  logic        quotient_negative_q;
  logic        remainder_negative_q;
  logic [31:0] dividend_q;
  logic [31:0] divisor_q;
  logic [31:0] quotient_q;
  logic [32:0] remainder_q;
  logic [5:0]  bit_index_q;

  logic [32:0] trial_remainder;
  logic        trial_ge_divisor;
  logic [32:0] remainder_after;
  logic [31:0] quotient_after;
  logic [31:0] rs1_abs;
  logic [31:0] rs2_abs;

  always_comb begin
    instr_div = 1'b0;
    instr_divu = 1'b0;
    instr_rem = 1'b0;
    instr_remu = 1'b0;
    if (pcpi_insn_i[6:0] == 7'b0110011 && pcpi_insn_i[31:25] == 7'b0000001) begin
      unique case (pcpi_insn_i[14:12])
        3'b100: instr_div = 1'b1;
        3'b101: instr_divu = 1'b1;
        3'b110: instr_rem = 1'b1;
        3'b111: instr_remu = 1'b1;
        default: begin
        end
      endcase
    end
    instr_any = instr_div || instr_divu || instr_rem || instr_remu;
    instr_signed = instr_div || instr_rem;
    instr_quotient = instr_div || instr_divu;

    rs1_abs = (instr_signed && pcpi_rs1_i[31]) ? (~pcpi_rs1_i + 32'd1) : pcpi_rs1_i;
    rs2_abs = (instr_signed && pcpi_rs2_i[31]) ? (~pcpi_rs2_i + 32'd1) : pcpi_rs2_i;

    trial_remainder = {remainder_q[31:0], dividend_q[bit_index_q]};
    trial_ge_divisor = trial_remainder >= {1'b0, divisor_q};
    remainder_after = trial_ge_divisor ?
                      (trial_remainder - {1'b0, divisor_q}) : trial_remainder;
    quotient_after = quotient_q;
    if (trial_ge_divisor) begin
      quotient_after[bit_index_q] = 1'b1;
    end
  end

  // A claimed instruction waits immediately and remains claimed until the
  // single response cycle. completed_q closes the one-cycle handoff window
  // while PicoRV32 drops PCPI_VALID after observing PCPI_READY.
  assign pcpi_wait_o = pcpi_valid_i && instr_any && !pcpi_ready_o && !completed_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      running_q <= 1'b0;
      completed_q <= 1'b0;
      quotient_negative_q <= 1'b0;
      remainder_negative_q <= 1'b0;
      dividend_q <= 32'h0000_0000;
      divisor_q <= 32'h0000_0000;
      quotient_q <= 32'h0000_0000;
      remainder_q <= 33'h0000_0000;
      bit_index_q <= 6'd0;
      pcpi_wr_o <= 1'b0;
      pcpi_rd_o <= 32'h0000_0000;
      pcpi_ready_o <= 1'b0;
    end else begin
      pcpi_wr_o <= 1'b0;
      pcpi_ready_o <= 1'b0;

      if (!pcpi_valid_i || !instr_any) begin
        running_q <= 1'b0;
        completed_q <= 1'b0;
      end else if (!running_q && !completed_q) begin
        // RISC-V defines division by zero without trapping. Handling it here
        // also avoids feeding a zero divisor through the iterative datapath.
        if (pcpi_rs2_i == 32'h0000_0000) begin
          pcpi_rd_o <= instr_quotient ? 32'hffff_ffff : pcpi_rs1_i;
          pcpi_wr_o <= 1'b1;
          pcpi_ready_o <= 1'b1;
          completed_q <= 1'b1;
        end else begin
          running_q <= 1'b1;
          dividend_q <= rs1_abs;
          divisor_q <= rs2_abs;
          quotient_q <= 32'h0000_0000;
          remainder_q <= 33'h0000_0000;
          bit_index_q <= 6'd31;
          quotient_negative_q <= instr_div && (pcpi_rs1_i[31] != pcpi_rs2_i[31]);
          remainder_negative_q <= instr_rem && pcpi_rs1_i[31];
        end
      end else if (running_q) begin
        if (bit_index_q == 6'd0) begin
          running_q <= 1'b0;
          completed_q <= 1'b1;
          pcpi_wr_o <= 1'b1;
          pcpi_ready_o <= 1'b1;
          if (instr_quotient) begin
            pcpi_rd_o <= quotient_negative_q ?
                         (~quotient_after + 32'd1) : quotient_after;
          end else begin
            pcpi_rd_o <= remainder_negative_q ?
                         (~remainder_after[31:0] + 32'd1) : remainder_after[31:0];
          end
        end else begin
          remainder_q <= remainder_after;
          quotient_q <= quotient_after;
          bit_index_q <= bit_index_q - 6'd1;
        end
      end
    end
  end

endmodule

`default_nettype wire
`endif
