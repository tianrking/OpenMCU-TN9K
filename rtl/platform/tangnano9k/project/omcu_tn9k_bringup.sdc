# 27 MHz board oscillator. The 37.037 ns period matches the current board
# reference project; nextpnr must report the derived system.clk_i domain.
create_clock -name clk_27m -period 37.037 [get_ports {clk_27m_i}]
