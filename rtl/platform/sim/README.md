# Simulation platform backend

The simulation backend will provide generic synchronous ROM/SRAM models, an
external QSPI flash model, GPIO loopbacks and UART/SPI/I2C test fixtures. It
must contain no Gowin primitives and must be the first place every public SDK
example runs.
