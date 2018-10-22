`timescale 1ns / 1ps

module ethernet_udp_tb();

    // Create a 100 MHz clock
    logic clk = 0;
    always clk = #5 ~clk;

    // Create a 25 MHz clock
    logic clk25 = 0;
    always clk25 = #20 ~clk25;

    // The reset signal
    logic reset = 0;

    // Indicates that the Ethernet module is powered on and ready
    logic ready;

    // Flushes the buffer
    logic flush = 0;

    // The signals to the Ethernet PHY
    EthernetPHY eth();
    logic eth_ref_clk;
    logic eth_rstn;
    logic eth_tx_clk;
    logic eth_tx_en;
    logic [3:0] eth_tx_d;
    assign eth_ref_clk = eth.ref_clk; // Out
    assign eth_rstn    = eth.rstn;    // Out
    assign eth.tx_clk  = eth_tx_clk;  // In
    assign eth_tx_en   = eth.tx_en;   // Out
    assign eth_tx_d    = eth.tx_d;    // Out
    // Make a 25 MHz clock from the reference clock
    assign eth_tx_clk = eth_ref_clk;

    // The IP info
    IPInfo ip_info();
    assign ip_info.src_ip    = 32'h55_66_77_88;
    assign ip_info.src_mac   = 48'haa_bb_cc_dd_ee_ff;
    assign ip_info.src_port  = 16'h1000;
    assign ip_info.dest_ip   = 32'h11_22_33_44;
    assign ip_info.dest_mac  = 48'h1a_2b_3c_4d_5e_6f;
    assign ip_info.dest_port = 16'h1000;

    // The signals to write data to the module
    logic wr_en = 0;
    logic [3:0] wr_data = '0;

    ethernet_udp_transmit #(
        .CLK_RATIO(4),
        .MAX_DATA_BYTES(480),
        .MIN_DATA_BYTES(16),
        .POWER_UP_CYCLES(100),
        .WORD_SIZE_BYTES(1))
    ethernet_udp_transmit(
        // Standard
        .clk(clk),
        .reset(reset),
        // Writing data
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_rst_busy(/* Unused */),
        .wr_full(/* Unused */),
        // Ethernet
        .clk25(clk25),
        .eth(eth),
        .flush(flush),
        .ip_info(ip_info),
        .ready(ready)
    );

    // Run the test
    initial begin
        // Reset the module
        reset <= 1;

        // Wait a while before deasserting the reset
        #100;
        reset <= 0;

        // Send the data
        #5000;
        for (int i = 0; i < 32; i++) begin
            wr_data <= i % 2 ? '0 : (32 - 1 - i) / 2;
            wr_en   <= 1;
            // Wait for one clock cycle
            #10;
        end
        wr_data <= '0;
        wr_en   <= 0;

        // Flush the buffer
        #500_000;
        // Send 3 bytes
        for (int i = 0; i < 6; i++) begin
            wr_data <= i % 2 ? '0 : (32 - 1 - i) / 2;
            wr_en   <= 1;
            // Wait for one clock cycle
            #10;
        end
        wr_data <= '0;
        wr_en   <= 0;
        #200;
        flush <= 1;
        #200;
        flush <= 0;
    end

    // The data is written to the PHY with the nibbles swapped (little endian
    // nibble order), so this flip flop inverts the nibbles and prints out the
    // bytes that were sent in big endian nibbles order.
    logic [7:0] rdata = '0;
    logic upper = 0;
    always_ff @(posedge eth.tx_clk) begin
        if (eth.tx_en) begin
            if (upper) begin
                rdata[7:4] = eth.tx_d;
                upper = 0;
                $display("%2H", rdata);
            end else begin
                rdata[3:0] = eth.tx_d;
                upper = 1;
            end
        end
    end

endmodule
