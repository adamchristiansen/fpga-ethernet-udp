`timescale 1ns / 1ps

module ethernet_udp_tb();

    // The parameters for the Ethernet nodule
    localparam int DATA_BYTES = 16;
    localparam int DIVIDER = 4;

    // Create a 100 MHz clock
    logic clk = 0;
    always clk = #5 ~clk;

    // The reset signal
    logic reset = 0;

    // Create the data
    logic [8*DATA_BYTES-1:0] data;
    generate
        for (genvar i = 0; i < DATA_BYTES; i++) begin
            assign data[8*i+:8] = i;
        end
    endgenerate

    // The signals to the Ethernet PHY
    EthernetPHY eth();
    logic eth_mdc;
    logic eth_mdio;
    logic eth_ref_clk;
    logic eth_rstn;
    logic eth_tx_clk;
    logic eth_tx_en;
    logic [3:0] eth_tx_d;
    assign eth_mdc     = eth.mdc;     // Out
    assign eth_mdio    = eth.mdio;    // In/Out
    assign eth_ref_clk = eth.ref_clk; // Out
    assign eth_rstn    = eth.rstn;    // Out
    assign eth.tx_clk  = eth_tx_clk;  // In
    assign eth_tx_en   = eth.tx_en;   // Out
    assign eth_tx_d    = eth.tx_d;    // Out
    // Make a 25 MHz clock from the reference clock
    assign eth_tx_clk = eth_ref_clk;

    // The IP info
    IPInfo ip_info;
    assign ip_info.src_ip    = 32'h55_66_77_88;
    assign ip_info.src_mac   = 48'haa_bb_cc_dd_ee_ff;
    assign ip_info.src_port  = 16'h1000;
    assign ip_info.dest_ip   = 32'h11_22_33_44;
    assign ip_info.dest_mac  = 48'h1a_2b_3c_4d_5e_6f;
    assign ip_info.dest_port = 16'h1000;

    // The module control and status signals
    logic ready;
    logic send = 0;

    // Instantiate the device under test
    ethernet_udp_transmit #(
        .DATA_BYTES(DATA_BYTES),
        .DIVIDER(DIVIDER),
        .POWER_UP_CYCLES(0)) dut_ethernet_transmit_udp(
        .clk(clk),
        .reset(reset),
        .data(data),
        .eth(eth),
        .ip_info(ip_info),
        .ready(ready),
        .send(send)
    );

    initial begin
        // Reset the module
        reset <= 1;

        // Wait a while before deassertiung the reset
        #100;
        reset <= 0;

        // Send the data
        #100;
        send <= 1;
        #100;
        send <= 0;
    end

endmodule
