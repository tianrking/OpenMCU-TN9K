`default_nettype none

package omcu_mmio_pkg;

  // Expands one byte-enable bit into the corresponding byte mask.
  function automatic logic [31:0] write_strobe_mask(input logic [3:0] strobe);
    logic [31:0] result;
    begin
      result = '0;
      for (int index = 0; index < 4; index++) begin
        result[index*8 +: 8] = {8{strobe[index]}};
      end
      return result;
    end
  endfunction

  // Merges a 32-bit write into a register without changing disabled bytes.
  function automatic logic [31:0] merge_write(
    input logic [31:0] old_value,
    input logic [31:0] write_value,
    input logic [3:0]  write_strobe
  );
    logic [31:0] mask;
    begin
      mask = write_strobe_mask(write_strobe);
      return (old_value & ~mask) | (write_value & mask);
    end
  endfunction

endpackage

`default_nettype wire
