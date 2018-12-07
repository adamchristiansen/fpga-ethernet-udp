`timescale 1ns / 1ps

/// This implements a basic echo server where the UART receiver is tied to the
/// transmitter.
///
/// # Ports
///
/// *   [clk] is the 100MHz off-chip clock.
/// *   [rst] is the active high system reset signal.
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
/// *   [led] is a set of status LEDs.
module main(
    // System
    input logic clk_ref,
    input logic rst,
    // Ethernet
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
    // Generate Clocks
    //-------------------------------------------------------------------------

    logic clk;
    logic clk25;

    clk_gen clk_gen(
        .clk_ref(clk_ref),
        .reset(rst),
        .clk100(clk),
        .clk25(clk25),
        .locked(/* Unused */)
    );

    //-------------------------------------------------------------------------
    // USB UART
    //-------------------------------------------------------------------------

    // The clock divider to get 115200Hz from 100MHz
    localparam int DIVIDER = 868;

    // The data received and sent on the UART.
    logic [7:0] uart_d;

    // Indicates that a byte was received on the UART.
    logic uart_recv_rdy;

    // This is a structure of parameters that descibes what to send.
    struct packed {
        logic [31:0] src_ip;
        logic [15:0] src_port;
        logic [47:0] src_mac;
        logic [31:0] dst_ip;
        logic [15:0] dst_port;
        logic [47:0] dst_mac;
        logic [7:0] seed;
        logic [7:0] gen;
    } params;

    // Indicates that the parameters have been received and are ready.
    logic params_rdy;

    // The number of bytes in the parameters.
    localparam int unsigned PARAM_BYTES = 26;

    // The index into the parameters for assigning bytes read on the UART.
    int unsigned params_i;

    uart_recv #(.DIVIDER(DIVIDER)) uart_recv(
        .clk(clk),
        .rst(rst),
        .rx(uart_rx),
        .d(uart_d),
        .rdy(uart_recv_rdy)
    );

    // Prepare the parameters for use in the UDP packet.
    always_ff @(posedge clk) begin
        if (rst) begin
            params_i    <= PARAM_BYTES - 1;
            params     <= '0;
            params_rdy <= 0;
        end else if (uart_recv_rdy) begin
            params[8*params_i+:8] <= uart_d;
            if (params_i == 0) begin
                params_i   <= PARAM_BYTES - 1;
                params_rdy <= 1;
            end else begin
                params_i   <= params_i - 1;
                params_rdy <= 0;
            end
        end else begin
            params_rdy <= 0;
        end
    end

    uart_send #(.DIVIDER(DIVIDER)) uart_send(
        .clk(clk),
        .rst(rst),
        .d(uart_d),
        .send(uart_recv_rdy),
        .rdy(/* Not connected */),
        .tx(uart_tx)
    );

    //-------------------------------------------------------------------------
    // Ethernet
    //-------------------------------------------------------------------------

    // The number of bytes to send in a UDP packet.
    localparam int unsigned DATA_BYTES = 256;

    // The data to be sent in a UDP packet.
    logic unsigned [8*DATA_BYTES-1:0] eth_d;

    // Starts writing data to the Ethernet module
    logic send_eth;

    // When there is new data from the UART, prepare the data to be sent over
    // Ethernet.
    always_ff @(posedge clk) begin
        if (rst) begin
            eth_d    <= '0;
            send_eth <= 0;
        end else if (params_rdy) begin
            for (int unsigned i = 0; i < DATA_BYTES; i++) begin
                eth_d[8*i+:8] <=
                    params.seed + (params.gen * (DATA_BYTES - 1 - i));
            end
            send_eth <= 1;
        end else begin
            send_eth <= 0;
        end
    end

    // The signals for writing to the MAC
    logic [3:0] wr_d;
    logic wr_en;

    // The index in the data that is being written to the MAC
    int wr_i;

    // Write the data to the MAC
    always_ff @(posedge clk) begin
        if (rst) begin
            wr_d  <= '0;
            wr_en <= 0;
            wr_i  <= -1;
        end else if (wr_i >= 0) begin
            wr_d  <= eth_d[8 * (wr_i >> 1) + 4 * ((~wr_i) & 1)+:4];
            wr_en <= 1;
            wr_i  <= wr_i - 1;
        end else if (send_eth) begin
            wr_en <= 0;
            wr_i  <= 2 * DATA_BYTES - 1;
        end else begin
            wr_en <= 0;
            wr_i  <= -1;
        end
    end

    // Instantiate an interface with the Ethernet PHY control signals
    IEthPhy eth();
    assign eth_ref_clk = eth.ref_clk; // Out
    assign eth_rstn    = eth.rstn;    // Out
    assign eth.tx_clk  = eth_tx_clk;  // In
    assign eth_tx_en   = eth.tx_en;   // Out
    assign eth_tx_d    = eth.tx_d;    // Out

    // The information needed to describe the source and the destination
    IIpInfo ip_info();
    assign ip_info.src_ip   = params.src_ip;
    assign ip_info.src_mac  = params.src_mac;
    assign ip_info.src_port = params.src_port;
    assign ip_info.dst_ip   = params.dst_ip;
    assign ip_info.dst_mac  = params.dst_mac;
    assign ip_info.dst_port = params.dst_port;

    // Indicates that the module has finished the startup sequence
    logic eth_rdy;

    // Indicates the Ethernet module is busy writing to the PHY
    logic eth_mac_busy;

    eth_udp_send #(
        .CLK_RATIO(4),
        .MIN_DATA_BYTES(DATA_BYTES),
        .POWER_UP_CYCLES(5_000_000),
        .WORD_SIZE_BYTES(1))
    eth_udp_send(
        // Standard
        .clk(clk),
        .rst(rst),
        // Writing data
        .wr_en(wr_en),
        .wr_d(wr_d),
        .wr_rst_busy(/* Unused */),
        .wr_full(/* Unused */),
        // Ethernet
        .clk25(clk25),
        .eth(eth),
        .flush(0),
        .ip_info(ip_info),
        .mac_busy(eth_mac_busy),
        .rdy(eth_rdy)
    );

    // When eth_rdy rises or eth_mac_busy falls, increment the LED counter
    logic eth_rdy_prev;
    logic eth_mac_busy_prev;
    always_ff @(posedge clk) begin
        if (rst) begin
            eth_rdy_prev      <= 1;
            eth_mac_busy_prev <= 0;
            led               <= '0;
        end else begin
            eth_rdy_prev      <= eth_rdy;
            eth_mac_busy_prev <= eth_mac_busy;
            if ((eth_mac_busy_prev && !eth_mac_busy) ||
                    (!eth_rdy_prev && eth_rdy)) begin
                led <= led + 1;
            end
        end
    end

endmodule
