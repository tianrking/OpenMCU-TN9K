# 27 MHz board oscillator. The 37.037 ns period matches the current board
# reference project; timing closure is still an unvalidated release gate.
create_clock -name clk_27m -period 37.037 -waveform {0 18.518} [get_ports {clk_27m_i}]
