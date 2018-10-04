# FPGA Ethernet UDP Transmitter

This project creates a module that can be used to interface with an Ethernet
PHY for transmitting UDP packets. Only transmission is supported, and there is
no receiver implemented on the FPGA.

This project was specifically built for and tested on the Digilent Arty A7,
which uses a Xilinx Artix-7 XC7A35T FPGA and has a Texas Instruments DP83848J
Ethernet PHY controller. However, the MII standard will work with any PHY.

## Building the HDL

Open Xilinx Vivado and select `Tools > Run Tcl Script...`, then select the
`generate_project.tcl` script in the file exporer. The script will run and
produce the Vivado project in a new `proj/` directory by importing all of the
project sources. If the project fails to be created, it is most likely that the
`proj/` directory already exists.

## Testing

The project can be tested using the the `ether_tester` program. The tester
generates a pseudo-random sequence of bytes on the FPGA to send over UDP, and
the test program verifies that the sequence it receives is correct.

To use the test program, make sure that Cargo is installed for compiling Rust
programs, then navigate to the `ether_tester` directory and run

```sh
cargo build
```

to download dependencies and build the project. To view the program help
information, run

```sh
cargo run -- -h
```

A sample invocation of the program is

```sh
cargo run --
    -b256
    --serial-port=/dev/ttyUSB1:115200
    --src=8.8.8.8:4096,aa:bb:cc:dd:ee:ff
    --dest=1.2.3.4:4096,00:11:22:33:44:55
    -r1000
```

In order, the arguments mean the following.

1.  Generate UDP packets with 256 vytes of data. This depends on the
    configuration of the FPGA.
2.  Set the serial port and baudrate to use. The baudrate depends on the FPGA
    configuration.
3.  Set the IP address, port number, and MAC address of the FPGA. These are
    dynamic and can be changed at any time. They do not depend on the FPGA
    configuration.
4.  Set the IP address, port number, and MAC address of the host to receive
    packets from the FPGA.
5.  Perform 1000 tests.
