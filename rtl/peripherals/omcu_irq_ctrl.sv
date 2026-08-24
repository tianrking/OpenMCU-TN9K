`default_nettype none

// OpenMCU's compact external interrupt controller.  It latches short
// peripheral events, provides a software-visible enable/acknowledge policy,
// and maps the six portable sources onto PicoRV32 external IRQ inputs 8..13.
// IRQ 0..2 are deliberately reserved for PicoRV32's timer, illegal-instruction
// and bus-error facilities, so a peripheral can never alias a core fault.
module omcu_irq_ctrl #(
  parameter integer SOURCE_COUNT = 6,
  parameter integer IRQ_BASE = 8
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,

  input  logic                    req_i,
  input  logic                    write_i,
  input  logic [31:0]             addr_i,
  input  logic [31:0]             write_data_i,
  input  logic [3:0]              write_strobe_i,
  output logic                    ready_o,
  output logic [31:0]             read_data_o,
  output logic                    error_o,

  input  logic [SOURCE_COUNT-1:0] source_i,
  output logic [31:0]             irq_o
);

  localparam logic [5:0] REG_PENDING = 6'h00;
  localparam logic [5:0] REG_ENABLE  = 6'h01;
  localparam logic [5:0] REG_CLEAR   = 6'h02;
  localparam logic [5:0] REG_FORCE   = 6'h03;
  localparam logic [5:0] REG_ACTIVE  = 6'h04;
  localparam logic [5:0] REG_HIGHEST = 6'h05;

  logic [SOURCE_COUNT-1:0] pending_q;
  logic [SOURCE_COUNT-1:0] enable_q;
  logic [SOURCE_COUNT-1:0] force_q;
  logic [SOURCE_COUNT-1:0] pending_sources;
  logic [SOURCE_COUNT-1:0] active_sources;
  logic [SOURCE_COUNT-1:0] enable_write_sources;
  logic [SOURCE_COUNT-1:0] command_write_sources;
  logic [31:0] pending_vector;
  logic [31:0] enable_vector;
  logic [31:0] active_vector;
  logic [31:0] merged_enable_vector;
  logic [31:0] write_strobe_mask;
  logic [31:0] highest_read;
  integer priority_index;

  function automatic logic [31:0] expand_sources(
    input logic [SOURCE_COUNT-1:0] sources
  );
    integer source_index;
    begin
      expand_sources = '0;
      for (source_index = 0; source_index < SOURCE_COUNT; source_index = source_index + 1) begin
        expand_sources[IRQ_BASE + source_index] = sources[source_index];
      end
    end
  endfunction

  function automatic logic [SOURCE_COUNT-1:0] compact_sources(
    input logic [31:0] vector
  );
    integer source_index;
    begin
      compact_sources = '0;
      for (source_index = 0; source_index < SOURCE_COUNT; source_index = source_index + 1) begin
        compact_sources[source_index] = vector[IRQ_BASE + source_index];
      end
    end
  endfunction

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign write_strobe_mask = `OMCU_WRITE_STROBE_MASK(write_strobe_i);
  assign pending_sources = pending_q | source_i | force_q;
  assign active_sources = pending_sources & enable_q;
  assign pending_vector = expand_sources(pending_sources);
  assign enable_vector = expand_sources(enable_q);
  assign active_vector = expand_sources(active_sources);
  assign irq_o = active_vector;
  assign merged_enable_vector = `OMCU_MERGE_WRITE(
    enable_vector,
    write_data_i,
    write_strobe_i
  );
  assign enable_write_sources = compact_sources(merged_enable_vector);
  assign command_write_sources = compact_sources(write_data_i & write_strobe_mask);

  always_comb begin
    // Lowest numbered active external IRQ wins.  The returned number is the
    // CPU IRQ bit index (8..13), not a register offset; zero means none.
    highest_read = '0;
    for (priority_index = 0;
         priority_index < SOURCE_COUNT;
         priority_index = priority_index + 1) begin
      if (active_sources[priority_index] && (highest_read == 32'h0000_0000)) begin
        highest_read = IRQ_BASE + priority_index;
      end
    end

    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_PENDING: read_data_o = pending_vector;
      REG_ENABLE:  read_data_o = enable_vector;
      REG_ACTIVE:  read_data_o = active_vector;
      REG_HIGHEST: read_data_o = highest_read;
      default:     read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_q <= '0;
      enable_q <= '0;
      force_q <= '0;
    end else begin
      // Level sources are converted into sticky pending bits. A short event
      // cannot be lost while software is masked or another IRQ is executing.
      pending_q <= pending_q | source_i;

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_ENABLE: begin
            enable_q <= enable_write_sources;
          end
          REG_CLEAR: begin
            // Source_i wins in the same clock so firmware cannot accidentally
            // discard a newly asserted peripheral event.
            pending_q <= (pending_q & ~command_write_sources) | source_i;
            force_q <= force_q & ~command_write_sources;
          end
          REG_FORCE: begin
            force_q <= force_q | command_write_sources;
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
