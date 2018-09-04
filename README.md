# FPGA Ethernet UDP Transmitter

This project creates a module that can be used to interface with an Ethernet
PHY for transmitting UDP packets. Only transmission is supported, and there is
no receiver implmented on the FPGA side of things.

This project was specifically built for and tested on the Digilent Arty A7,
which uses a Xilinx Artix-7 XC7A35T FPGA and has a Texas Instruments DP83848J
Ethernet PHY controller.

## Building the HDL

Open Xilinx Vivado and select `Tools > Run Tcl Script...`, then select the
`generate_project.tcl` script in the file exporer. The script will run and
produce the Vivado project in a new `proj/` directory by importing all of the
project sources. If the project fails to be created, it is most likely that the
`proj/` directory already exists.
