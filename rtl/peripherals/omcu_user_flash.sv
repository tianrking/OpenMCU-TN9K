`default_nettype none

// Tang Nano 9K user-flash transaction adapter.
//
// The GW1NR-9C exposes 608 Kbit of user flash separately from the FPGA
// configuration image.  This block presents it as a byte-addressed CPU memory
// window.  Reads return a 32-bit word, aligned 32-bit writes program one word,
// and an 8-bit write erases the containing 2 KiB page.  Those intentionally
// narrow write rules make destructive erase/program operations explicit in
// firmware.
//
// Product wrappers select the documented FLASH608K primitive; generic RTL
// builds select a deterministic behavioural model instead. The model is never
// a substitute for hardware programming validation.
module omcu_user_flash #(
  parameter integer FLASH_BYTES = 77824,
  parameter integer CLOCK_HZ = 27000000,
  parameter integer PRESENT = 0,
  // Product wrappers set this to use the vendor FLASH608K primitive. Generic
  // simulation keeps it clear and uses the deterministic model below.
  parameter integer USE_GOWIN_USER_FLASH = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  // The product connects TIMER0's tick and low count bits. Software selects
  // the operation prescaler and resets COUNT before each destructive access.
  input  logic        timebase_tick_i,
  input  logic [16:0] timebase_count_i,

  input  logic        req_i,
  input  logic        write_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] write_data_i,
  input  logic [3:0]  write_strobe_i,
  output logic        ready_o,
  output logic [31:0] read_data_o,
  output logic        error_o
);

  localparam integer PAGE_BYTES = 2048;
  localparam integer PAGE_WORDS = PAGE_BYTES / 4;
  localparam integer FLASH_WORDS = (FLASH_BYTES + 3) / 4;
  // Generic builds deliberately instantiate an absent, four-byte window.
  // Keep the behavioural array and its address width legal in that case too;
  // the range/PRESENT checks below still make every access fail cleanly.
  localparam integer MODEL_WORDS =
    (FLASH_WORDS < PAGE_WORDS) ? PAGE_WORDS : FLASH_WORDS;
  localparam integer FLASH_ADDR_BITS = $clog2(MODEL_WORDS);

  // Absolute phase deadlines reuse TIMER0, avoiding a second 17-bit timer in
  // the nearly full GW1NR-9C. The bootloader selects a documented operation
  // prescaler before resetting COUNT: divide-by-21 for program and divide-by-26
  // for erase. All values fit below the counter's low-17-bit wrap.
  localparam logic [16:0] PROGRAM_SETUP_TERMINAL = 17'd9;
  localparam logic [16:0] PROGRAM_NVSTR_TERMINAL = 17'd24;
  localparam logic [16:0] PROGRAM_YE_TERMINAL = 17'd44;
  localparam logic [16:0] PROGRAM_RELEASE_TERMINAL = 17'd54;
  localparam logic [16:0] PROGRAM_FINISH_TERMINAL = 17'd69;
  localparam logic [16:0] ERASE_SETUP_TERMINAL = 17'd9;
  // At the erase prescaler these deadlines produce about 115.6 ms of high
  // voltage, centered safely inside the documented 100--120 ms window.
  localparam logic [16:0] ERASE_NVSTR_TERMINAL = 17'd120019;
  localparam logic [16:0] ERASE_RELEASE_TERMINAL = 17'd120029;
  localparam logic [16:0] ERASE_FINISH_TERMINAL = 17'd120044;

  localparam logic [4:0] STATE_IDLE = 5'd0;
  localparam logic [4:0] STATE_READ_ASSERT = 5'd1;
  localparam logic [4:0] STATE_READ_CAPTURE = 5'd2;
  localparam logic [4:0] STATE_ERASE_SETUP = 5'd3;
  localparam logic [4:0] STATE_ERASE_NVSTR = 5'd4;
  localparam logic [4:0] STATE_ERASE_RELEASE = 5'd5;
  localparam logic [4:0] STATE_ERASE_FINISH = 5'd6;
  localparam logic [4:0] STATE_PROGRAM_SETUP = 5'd7;
  localparam logic [4:0] STATE_PROGRAM_NVSTR = 5'd8;
  localparam logic [4:0] STATE_PROGRAM_YE = 5'd9;
  localparam logic [4:0] STATE_PROGRAM_HOLD = 5'd10;
  localparam logic [4:0] STATE_PROGRAM_RELEASE = 5'd11;
  localparam logic [4:0] STATE_PROGRAM_FINISH = 5'd12;
  localparam logic [4:0] STATE_DONE = 5'd13;

  logic [4:0] state_q;
  logic [31:0] addr_q;
  logic [31:0] write_data_q;
  logic [31:0] read_data_q;
  logic [16:0] phase_terminal;
  logic error_q;

  logic flash_xe;
  logic flash_ye;
  logic flash_se;
  logic flash_prog;
  logic flash_erase;
  logic flash_nvstr;
  wire [31:0] flash_dout;
  logic [31:0] physical_flash_dout;

  wire [FLASH_ADDR_BITS-1:0] word_index = addr_q[FLASH_ADDR_BITS+1:2];
  wire [FLASH_ADDR_BITS-1:0] page_word_index =
    (word_index / PAGE_WORDS) * PAGE_WORDS;
  wire address_in_range = (addr_q < FLASH_BYTES);
  wire phase_done = timebase_tick_i && (timebase_count_i == phase_terminal);

  generate
    if ((PRESENT != 0) && (USE_GOWIN_USER_FLASH != 0)) begin : physical_flash
      // FLASH608K is a documented GW1NR-9C primitive.  Do not replace this
      // primitive with a configuration-flash interface: user flash is a
      // distinct nonvolatile resource and is what makes MCU firmware updates
      // independent from the FPGA bitstream.
      FLASH608K flash_primitive (
        .DOUT(physical_flash_dout),
        .XE(flash_xe),
        .YE(flash_ye),
        .SE(flash_se),
        .PROG(flash_prog),
        .ERASE(flash_erase),
        .NVSTR(flash_nvstr),
        // FLASH608K takes a 15-bit *word* address, split as XADR[8:0]
        // and YADR[5:0].  The CPU-facing window is byte addressed, hence
        // the two-bit conversion here (equivalent to address[16:2]).
        .XADR(addr_q[16:8]),
        .YADR(addr_q[7:2]),
        .DIN(write_data_q)
      );
      assign flash_dout = physical_flash_dout;
    end else if (PRESENT != 0) begin : behavioural_flash
      // Keep the simulation array entirely out of a physical product build.
      // A 76 KiB array would otherwise be elaborated before generate pruning
      // and can exhaust lightweight WebAssembly synthesis environments.
      logic [31:0] flash_model [0:MODEL_WORDS-1];
      integer model_init_index;
      integer model_erase_index;

      initial begin
        for (model_init_index = 0; model_init_index < MODEL_WORDS;
             model_init_index = model_init_index + 1) begin
          flash_model[model_init_index] = 32'h0000_0000;
        end
      end

      assign flash_dout = address_in_range ? flash_model[word_index]
                                            : 32'h0000_0000;

      always_ff @(posedge clk_i) begin
        if (rst_ni && state_q == STATE_ERASE_FINISH && phase_done) begin
          for (model_erase_index = 0;
               model_erase_index < PAGE_WORDS;
               model_erase_index = model_erase_index + 1) begin
            if ((page_word_index + model_erase_index) < FLASH_WORDS) begin
              flash_model[page_word_index + model_erase_index] <= 32'h0000_0000;
            end
          end
        end
        if (rst_ni && state_q == STATE_PROGRAM_YE && phase_done) begin
          flash_model[word_index] <= flash_model[word_index] | write_data_q;
        end
      end
    end else begin : absent_flash
      assign physical_flash_dout = 32'h0000_0000;
      assign flash_dout = 32'h0000_0000;
    end
  endgenerate

  assign ready_o = (state_q == STATE_DONE);
  assign read_data_o = read_data_q;
  assign error_o = ready_o && error_q;

  always_comb begin
    flash_xe = 1'b0;
    flash_ye = 1'b0;
    flash_se = 1'b0;
    flash_prog = 1'b0;
    flash_erase = 1'b0;
    flash_nvstr = 1'b0;
    phase_terminal = PROGRAM_SETUP_TERMINAL;

    unique case (state_q)
      STATE_READ_ASSERT: begin
        flash_xe = 1'b1;
        flash_ye = 1'b1;
      end
      STATE_READ_CAPTURE: begin
        flash_xe = 1'b1;
        flash_ye = 1'b1;
        flash_se = !error_q;
      end
      STATE_ERASE_SETUP: begin
        flash_xe = 1'b1;
        flash_erase = error_q;
        phase_terminal = ERASE_SETUP_TERMINAL;
      end
      STATE_ERASE_NVSTR: begin
        flash_xe = 1'b1;
        flash_erase = 1'b1;
        flash_nvstr = 1'b1;
        phase_terminal = ERASE_NVSTR_TERMINAL;
      end
      STATE_ERASE_RELEASE: begin
        flash_xe = 1'b1;
        flash_nvstr = 1'b1;
        phase_terminal = ERASE_RELEASE_TERMINAL;
      end
      STATE_ERASE_FINISH: begin
        flash_xe = 1'b1;
        phase_terminal = ERASE_FINISH_TERMINAL;
      end
      STATE_PROGRAM_SETUP: begin
        flash_xe = 1'b1;
        flash_prog = error_q;
        phase_terminal = PROGRAM_SETUP_TERMINAL;
      end
      STATE_PROGRAM_NVSTR: begin
        flash_xe = 1'b1;
        flash_prog = 1'b1;
        flash_nvstr = 1'b1;
        phase_terminal = PROGRAM_NVSTR_TERMINAL;
      end
      STATE_PROGRAM_YE: begin
        flash_xe = 1'b1;
        flash_ye = 1'b1;
        flash_prog = 1'b1;
        flash_nvstr = 1'b1;
        phase_terminal = PROGRAM_YE_TERMINAL;
      end
      STATE_PROGRAM_HOLD: begin
        flash_xe = 1'b1;
        flash_prog = 1'b1;
        flash_nvstr = 1'b1;
      end
      STATE_PROGRAM_RELEASE: begin
        flash_xe = 1'b1;
        flash_nvstr = 1'b1;
        phase_terminal = PROGRAM_RELEASE_TERMINAL;
      end
      STATE_PROGRAM_FINISH: begin
        flash_xe = 1'b1;
        phase_terminal = PROGRAM_FINISH_TERMINAL;
      end
      default: begin
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= STATE_IDLE;
      addr_q <= 32'h0000_0000;
      write_data_q <= 32'h0000_0000;
      read_data_q <= 32'h0000_0000;
      error_q <= 1'b0;
    end else begin
      unique case (state_q)
        STATE_IDLE: begin
          error_q <= 1'b0;
          if (req_i) begin
            addr_q <= addr_i;
            write_data_q <= write_data_i;
            if (PRESENT == 0 || addr_i >= FLASH_BYTES) begin
              error_q <= 1'b1;
              state_q <= STATE_DONE;
            end else if (!write_i) begin
              state_q <= STATE_READ_ASSERT;
            end else if ((write_strobe_i == 4'b1111) &&
                         (addr_i[1:0] == 2'b00)) begin
              state_q <= STATE_PROGRAM_SETUP;
            end else if (write_strobe_i == 4'b0001) begin
              state_q <= STATE_ERASE_SETUP;
            end else begin
              error_q <= 1'b1;
              state_q <= STATE_DONE;
            end
          end
        end

        STATE_READ_ASSERT: begin
          state_q <= STATE_READ_CAPTURE;
        end
        STATE_READ_CAPTURE: begin
          if (!error_q) begin
            error_q <= 1'b1;
          end else begin
            read_data_q <= flash_dout;
            error_q <= 1'b0;
            state_q <= STATE_DONE;
          end
        end

        STATE_ERASE_SETUP: begin
          if (!error_q) begin
            // FLASH608K requires XE to precede ERASE/PROG by at least 5 ns.
            // At 27 MHz this phase supplies a conservative full clock.
            error_q <= 1'b1;
          end else if (phase_done) begin
            state_q <= STATE_ERASE_NVSTR;
          end
        end

        STATE_ERASE_NVSTR: begin
          if (phase_done) begin
            state_q <= STATE_ERASE_RELEASE;
          end
        end
        STATE_ERASE_RELEASE: begin
          if (phase_done) begin
            state_q <= STATE_ERASE_FINISH;
          end
        end
        STATE_ERASE_FINISH: begin
          if (phase_done) begin
            error_q <= 1'b0;
            state_q <= STATE_DONE;
          end
        end

        STATE_PROGRAM_SETUP: begin
          if (!error_q) begin
            error_q <= 1'b1;
          end else if (phase_done) begin
            state_q <= STATE_PROGRAM_NVSTR;
          end
        end
        STATE_PROGRAM_NVSTR: begin
          if (phase_done) begin
            state_q <= STATE_PROGRAM_YE;
          end
        end
        STATE_PROGRAM_YE: begin
          if (phase_done) begin
            state_q <= STATE_PROGRAM_HOLD;
          end
        end

        STATE_PROGRAM_HOLD: begin
          // FLASH608K requires address/data to remain stable for at least
          // 20 ns after YE falls. One 27 MHz product clock is about 37 ns.
          state_q <= STATE_PROGRAM_RELEASE;
        end
        STATE_PROGRAM_RELEASE: begin
          if (phase_done) begin
            state_q <= STATE_PROGRAM_FINISH;
          end
        end
        STATE_PROGRAM_FINISH: begin
          if (phase_done) begin
            error_q <= 1'b0;
            state_q <= STATE_DONE;
          end
        end
        STATE_DONE: begin
          state_q <= STATE_IDLE;
        end

        default: begin
          error_q <= 1'b1;
          state_q <= STATE_DONE;
        end
      endcase
    end
  end

endmodule

`default_nettype wire
