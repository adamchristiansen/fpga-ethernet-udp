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
/// *   [uart_rx] is the receive end of the serial.
/// *   [uart_tx] is the transmit end of the serial.
module main(
    // System
    input logic clk,
    input logic reset,
    // Ethernet
    output logic eth_mdc,
    inout logic eth_mdio,
    output logic eth_ref_clk,
    output logic eth_rstn,
    input logic eth_tx_clk,
    output logic eth_tx_en,
    output logic unsigned [3:0] eth_tx_d,
    // USB UART
    input logic uart_rx,
    output logic uart_tx,
    // Others
    output logic [3:0] led);

    //-------------------------------------------------------------------------
    // USB UART
    //-------------------------------------------------------------------------

    // The clock divider to get 115200Hz from 100MHz
    localparam int DIVIDER = 868;

    // The data received and sent on the UART.
    logic [7:0] uart_data;

    // Indicates that a byte was received on the UART.
    logic uart_receive_ready;

    // This is a structure of parameters that descibes what to send.
    struct packed {
        logic [32:0] src_ip;
        logic [47:0] src_mac;
        logic [15:0] src_port;
        logic [32:0] dest_ip;
        logic [47:0] dest_mac;
        logic [15:0] dest_port;
        logic [7:0] seed;
        logic [7:0] generator;
    } params;

    // Indicates that the parameters have been received and are ready.
    logic params_ready;

    // The number of bytes in the parameters.
    localparam int unsigned PARAM_BYTES = 26;

    // The index into the parameters for assigning bytes read on the UART.
    int unsigned param_index;

    uart_receive #(.DIVIDER(DIVIDER)) uart_receive(
        .clk(clk),
        .reset(reset),
        .rx(uart_rx),
        .data(uart_data),
        .ready(uart_receive_ready)
    );

    // Prepare the parameters for use in the UDP packet.
    always_ff @(posedge clk) begin
        if (reset) begin
            param_index <= PARAM_BYTES - 1;
            params      <= '0;
            params_ready <= 0;
        end else if (uart_receive_ready) begin
            params[8*param_index+:8] <= uart_data;
            if (param_index == 0) begin
                param_index  <= PARAM_BYTES - 1;
                params_ready <= 1;
            end else begin
                param_index <= param_index - 1;
                params_ready <= 0;
            end
        end else begin
            params_ready <= 0;
        end
    end

    uart_transmit #(.DIVIDER(DIVIDER)) uart_transmit(
        .clk(clk),
        .reset(reset),
        .data(uart_data),
        .send(uart_receive_ready),
        .ready(/* Not connected */),
        .tx(uart_tx)
    );

    //-------------------------------------------------------------------------
    // Ethernet
    //-------------------------------------------------------------------------

    // The number of bytes to send in a UDP packet.
    localparam int unsigned DATA_BYTES = 256;

    // The data to be sent in a UDP packet.
    logic unsigned [8*DATA_BYTES-1:0] eth_data;

    // Indicates that the current data should be sent over UDP.
    logic send_eth;

    // When there is new data from the UART, prepare the data to be sent over
    // Ethernet.
    always_ff @(posedge clk) begin
        if (reset) begin
            eth_data <= '0;
            send_eth <= 0;
        end else if (params_ready) begin
            for (int unsigned i = 0; i < DATA_BYTES; i++) begin
                eth_data[8*i+:8] <= params.seed + (params.generator * i);
            end
            send_eth <= 1;
        end else begin
            send_eth <= 0;
        end
    end

    // Instantiate an interface with the Ethernet PHY control signals
    EthernetPHY eth();
    assign eth_mdc     = eth.mdc;     // Out
    assign eth_mdio    = eth.mdio;    // In/Out
    assign eth_ref_clk = eth.ref_clk; // Out
    assign eth_rstn    = eth.rstn;    // Out
    assign eth.tx_clk  = eth_tx_clk;  // In
    assign eth_tx_en   = eth.tx_en;   // Out
    assign eth_tx_d    = eth.tx_d;    // Out

    // The information needed to describe the source and the destination
    IPInfo ip_info;
    assign ip_info.src_ip    = params.src_ip;
    assign ip_info.src_mac   = params.src_mac;
    assign ip_info.src_port  = params.src_port;
    assign ip_info.dest_ip   = params.dest_ip;
    assign ip_info.dest_mac  = params.dest_mac;
    assign ip_info.dest_port = params.dest_port;

    // Indicates the Ethernet module is ready to send data
    logic eth_ready;

    ethernet_udp_transmit #(.DATA_BYTES(DATA_BYTES), .DIVIDER(4))
    ethernet_udp_transmit(
        // Standard
        .clk(clk),
        .reset(reset),
        // Ethernet
        .data(eth_data),
        .eth(eth),
        .ip_info(ip_info),
        .ready(eth_ready),
        .send(send_eth)
    );

    // When eth_ready rises, increment the LED counter
    logic eth_ready_prev;
    always_ff @(posedge clk) begin
        if (reset) begin
            eth_ready_prev <= 1;
            led            <= '0;
        end else begin
            eth_ready_prev <= eth_ready;
            if (!eth_ready_prev && eth_ready) begin
                led <= led + 1;
            end
        end
    end

endmodule
