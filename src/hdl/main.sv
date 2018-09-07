`timescale 1ns / 1ps

/// This implements a basic echo server where the UART receiver is tied to the
/// transmitter.
///
/// # Ports
///
/// *   [clk] is the 100MHz off-chip clock.
/// *   [reset] is the active high system reset signal.
/// *   [eth_crs] is the carrier sense signal. It is driven high when the
///     medium is busy.
/// *   [eth_mdc] is the clock for communicating over MDIO, with a maximum rate
///     of 25MHz.
/// *   [eth_mdio] is a bidrectional data signal for instructions.
/// *   [eth_ref_clk] is the reference clock input. This must be connected to a
///     25MHz clock source.
/// *   [eth_rstn] is an active low reset. This signal must be asserted for at
///     least 1 µs for a reset event to get triggered.
/// *   [eth_tx_clk] is the clock to transmit data on. This will have two
///     values depending on the mode. In the 10 Mb/s mode, this will be
///     2.5 MHz. In the 100 Mb/s mode, this will be 25 MHz.
/// *   [eth_tx_en] is the transmit enable. This is an active high indicator
///     that the value on [eth_rx_d] is valid.
/// *   [eth_tx_d] is the data to transmit.
/// *   [usb_rx] is the receive end of the serial.
/// *   [usb_tx] is the transmit end of the serial.
/// *   [led] is a bus of LEDs used for indicating status.
/// *   [send_eth] tells the ethernet module to send data on the rising edge.
module main(
    // System
    input logic clk,
    input logic reset,
    // Ethernet
    input logic eth_crs,
    output logic eth_mdc,
    inout logic eth_mdio,
    output logic eth_ref_clk,
    output logic eth_rstn,
    input logic eth_tx_clk,
    output logic eth_tx_en,
    output logic unsigned [3:0] eth_tx_d,
    // USB UART
    input logic usb_rx,
    output logic usb_tx,
    // General IO
    output logic [3:0] led,
    input logic send_eth);

    //-------------------------------------------------------------------------
    // Ethernet
    //-------------------------------------------------------------------------

    // Instantiate an interface with the Ethernet PHY control signals
    EthernetPHY eth();
    assign eth.crs     = eth_crs;
    assign eth.mdc     = eth_mdc;
    assign eth.mdio    = eth_mdio;
    assign eth.ref_clk = eth_ref_clk;
    assign eth.rstn    = eth_rstn;
    assign eth.tx_clk  = eth_tx_clk;
    assign eth.tx_en   = eth_tx_en;
    assign eth.tx_d    = eth_tx_d;

    // The width of the data to send
    localparam int DW = 8;

    // The data to send over Ethernet
    logic [63:0] data;
    assign data[63:56] = 8'b1111_0000;
    assign data[55:48] = 8'b0101_0101;
    assign data[47:40] = 8'b0111_0010;
    assign data[39:32] = 8'b0100_1000;
    assign data[31:24] = 8'b0001_0001;
    assign data[23:16] = 8'b0110_0000;
    assign data[15:8]  = 8'b0000_1100;
    assign data[7:0]   = 8'b1111_0000;

    // The information needed to describe the source and the destination
    IPInfo ip_info;
    assign ip_info.src_ip    = '0;
    assign ip_info.src_mac   = '0;
    assign ip_info.src_port  = '0;
    assign ip_info.dest_ip   = '0;
    assign ip_info.dest_mac  = '0;
    assign ip_info.dest_port = '0;

    ethernet_udp_transmit #(.DATA_WIDTH(DW), .DIVIDER(4))
    ethernet_udp_transmit(
        // Standard
        .clk(clk),
        .reset(reset),
        // Ethernet
        .data(data),
        .eth(eth),
        .ip_info(ip_info),
        .ready(led[0]),
        .send(send_eth)
    );

    // The rest of the LEDs are unused
    assign led[3:1] = '0;

    //-------------------------------------------------------------------------
    // USB UART
    //-------------------------------------------------------------------------

    // TODO Set parameters over serial. For now, this is just an echo server

    // The clock divider to get 115200Hz from 100MHz
    localparam int DIVIDER = 868;

    // The data received and sent over serial
    logic [7:0] usb_data;

    // Indicates that a byte was received
    logic receive_ready;

    uart_receive #(.DIVIDER(DIVIDER)) uart_receive(
        .clk(clk),
        .reset(reset),
        .rx(usb_rx),
        .data(usb_data),
        .ready(receive_ready)
    );

    uart_transmit #(.DIVIDER(DIVIDER)) uart_transmit(
        .clk(clk),
        .reset(reset),
        .data(usb_data),
        .send(receive_ready),
        .ready(/* Not connected */),
        .tx(usb_tx)
    );

endmodule
