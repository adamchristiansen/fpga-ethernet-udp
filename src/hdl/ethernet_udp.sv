`timescale 1ns / 1ps

// NOTE: Technical language generally uses the term _octet_ to describe a group
// of 8-bits. This is because the term _bytes_ is not actually well defined.
// There is no reason that a byte must be 8 bits. A byte is the smallest
// addressable unit in a system, which historically and practically has been
// designated 8 bits. There is not reason that a byte couldn't be 16, 32, 5,
// 19, or any other number of bits. However, in the implementation of this
// module, it will be assumed that octects and bytes are equivalent and
// interchangeable.

// NOTE: In the specification of the Internet protocols (RFCs), the terminalogy
// is a bit confusing. The RFCs use big-endian format, but the bit labelling is
// different than usual. The RFCs label the MSB as 0, whereas typically the LSB
// is 0. The code uses the format where the LSBs are 0, but the comments which
// reference RFCs use the MSB as 0 to be consistent with them.

/// This is the header of an Ethernet frame.
///
/// # Fields
///
/// *   [dest_mac] is the destination MAC address.
/// *   [src_mac] is the source MAC address.
/// *   [ether_type] indicates the protocol of the packet being sent.
typedef struct packed {
    logic unsigned [47:0] dest_mac;
    logic unsigned [47:0] src_mac;
    logic unsigned [15:0] ether_type;
} EthernetHeader;

/// According to RFC 791, an IP header has the following format
///
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +---------------+---------------+---------------+---------------+
/// |Version|  IHL  |     Type      |          Total Length         |
/// +---------------+---------------+---------------+---------------+
/// |         Identification        |Flags|     Fragment Offset     |
/// +---------------+---------------+---------------+---------------+
/// | Time to Live  |    Protocol   |        Header Checksum        |
/// +---------------+---------------+---------------+---------------+
/// |                       Source IP Address                       |
/// +---------------+---------------+---------------+---------------+
/// |                    Destination IP Address                     |
/// +---------------+---------------+---------------+---------------+
///
/// # Fields
///
/// *   [version] indicates the format of internet header.
/// *   [ihl] is the internet header length. This must be at least 5.
/// *   [type_of_service] is the type and quality of service desired.
/// *   [total_length] is the total length of packet including the header and
///     data.
/// *   [identification] is  assigned to help with assembling fragments.
/// *   [flags] is a set of control flags.
/// *   [fragment_offset] indicates where in a datagram the fragment belongs.
/// *   [time_to_live] the time (formally in seconds, practically in hops) that
///     the datagram is allowed to live.
/// *   [protocol] the next level protocol to use.
/// *   [header_checksum] is the checksum that verifies the validity of the
///     IP header.
/// *   [source_ip] is the source IPv4 address.
/// *   [dest_ip] is the destination IPv4 address.
typedef struct packed {
    logic unsigned [3:0] version;
    logic unsigned [3:0] ihl;
    logic unsigned [7:0] type_of_service;
    logic unsigned [15:0] total_length;
    logic unsigned [15:0] identification;
    logic unsigned [2:0] flags;
    logic unsigned [13:0] fragment_offset;
    logic unsigned [7:0] time_to_live;
    logic unsigned [7:0] protocol;
    logic unsigned [15:0] header_checksum;
    logic unsigned [31:0] src_ip;
    logic unsigned [31:0] dest_ip;
} IPHeader;

/// According to RFC 768, the UDP header has the following format
///
///  0      7 8     15 16    23 24    31
/// +--------+--------+--------+--------+
/// |   Source Port   |    Dest Port    |
/// +--------+--------+--------+--------+
/// |     Length      |    Checksum     |
/// +--------+--------+--------+--------+
///
/// # Fields
///
/// *   [src_port] is the number of the source port.
/// *   [dest_port] is the number of the destination port.
/// *   [length] is the length of the packet in bytes inclufing this header.
/// *   [checksum] is the UDP checksum.
typedef struct packed {
    logic unsigned [15:0] src_port;
    logic unsigned [15:0] dest_port;
    logic unsigned [15:0] length;
    logic unsigned [15:0] checksum;
} UDPHeader;

/// Holds the values needed to describe the source and destination of an IP
/// packet.
///
/// # Fields
///
/// *   [src_ip] is the source IP address.
/// *   [src_mac] is the source MAC address.
/// *   [src_port] is the source port number.
/// *   [dest_ip] is the destination IP address.
/// *   [dest_mac] is the destination MAC address.
/// *   [dest_port] is the destination port number.
typedef struct packed {
    logic unsigned [31:0] src_ip;
    logic unsigned [47:0] src_mac;
    logic unsigned [15:0] src_port;
    logic unsigned [31:0] dest_ip;
    logic unsigned [47:0] dest_mac;
    logic unsigned [15:0] dest_port;
} IPInfo;

/// Holds the signals that control the Ethernet PHY.
///
/// # Ports
///
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
///     2.5 MHz.In the 100 Mb/s mode, this will be 25 MHz.
/// *   [eth_tx_en] is the transmit enable. This is an active high indicator
///     that the value on [eth_rx_d] is valid.
/// *   [eth_tx_d] is the data to transmit.
///
/// # Mod Ports
///
/// *   [fwd] forwards the ports while preserving the port directions to
///     communicate with the PHY.
interface EthernetPHY;
    logic crs;
    logic mdc;
    logic mdio;
    logic ref_clk;
    logic rstn;
    logic tx_clk;
    logic tx_en;
    logic unsigned [3:0] tx_d;

    modport fwd(
        input crs,
        output mdc,
        inout mdio,
        output ref_clk,
        output rstn,
        input tx_clk,
        output tx_en,
        output tx_d);
endinterface

/// This module implements a transmitter for an Ethernet port. This is used to
/// send UDP packets using IPv4.
///
/// The [DATA_BYTES] parameter describes the maximum width (in bytes) that the
/// module should be prepared to transmit through the [data] port. Here is a
/// summary of the most important information sourced from RFCs.
///
/// *   RFC 768: a UDP header is 8 bytes.
/// *   RFC 791: the maximum sized internet header is 60 bytes.
/// *   RFC 791: every host must be able to receive a datagram of at least 576
///     bytes.
///
/// These specifications imply that the safest maximum size of a UDP payload is
/// 576 - 60 - 8 = 508 bytes.
///
/// # Parameters
///
/// *   [DATA_BYTES] is the width in bytes to be transmitted in the payload of
///     each UDP packet.
/// *   [DIVIDER] is the value of a clock divider that is used to generate a
///     new clock from the system clock. The new clock is used to write to the
///     Ethernet PHY. The divider must be large enough so that the produced
///     clock is no faster than 25MHz (which is the max speed supported by the
///     10/100 PHY).
///
/// # Ports
///
/// *   [clk] is the system clock.
/// *   [reset] is the system reset signal.
/// *   [data] is the bus of data to be transmitted over the port.
/// *   [eth] contains the signals used to write to the Ethernet PHY.
/// *   [ip_info] is the source and destination data that is needed to transmit
///     the packet.
/// *   [send] is a rising edge active signal that starts sending the [data].
/// *   [data] to be sent in the current packet. Set this to 0 to always send
///     the entire [data] register.
/// *   [ready] indicates that the module is ready to accept a [send] signal to
///     transmit more data. This is held high while ready and falls when the
/// *   [send] signal rises.
module ethernet_udp_transmit #(
    parameter int DATA_BYTES = 0,
    parameter int DIVIDER = 0) (
    // Standard
    input logic clk,
    input logic reset,
    // Ethernet
    input logic unsigned [8*DATA_BYTES-1:0] data,
    EthernetPHY.fwd eth,
    input IPInfo ip_info,
    output logic ready,
    input logic send);

    // Assert that the parameters are appropriate
    initial begin
        // Check that the DATA_BYTES is set appropriately
        if (DATA_BYTES <= 0) begin
            $error("The DATA_BYTES must be set to a positive number.");
        end
        if (DATA_BYTES > 508) begin
            $error("The DATA_BYTES must be less than or equal to 508.");
        end
        // Check that the clock divider is set appropriately
        if (DIVIDER < 2) begin
            $error("The DIVIDER must be set to at least 2.");
        end
    end

    // The number of bytes in parts of the frame.
    localparam int unsigned PREAMBLE_SFD_BYTES = 8;
    localparam int unsigned ETHER_HEADER_BYTES = 14;
    localparam int unsigned IP_HEADER_BYTES = 20;
    localparam int unsigned UDP_HEADER_BYTES = 8;
    localparam int unsigned FCS_BYTES = 4;

    // The total number of bytes in the IP packet.
    localparam int unsigned IP_BYTES =
        IP_HEADER_BYTES + UDP_HEADER_BYTES + DATA_BYTES;

    // The total number of bytes in the UDP packet.
    localparam int unsigned UDP_BYTES = UDP_HEADER_BYTES + DATA_BYTES;

    // The number of nibbles in parts of the frame.
    localparam int unsigned PREAMBLE_SFD_NIBBLES = 2 * PREAMBLE_SFD_BYTES;
    localparam int unsigned ETHER_HEADER_NIBBLES = 2 * ETHER_HEADER_BYTES;
    localparam int unsigned IP_HEADER_NIBBLES = 2 * IP_HEADER_BYTES;
    localparam int unsigned UDP_HEADER_NIBBLES = 2 * UDP_HEADER_BYTES;
    localparam int unsigned DATA_NIBBLES = 2 * DATA_BYTES;
    localparam int unsigned FCS_NIBBLES = 2 * DATA_BYTES;

    // The number of nibbles send not counting the preamble and SFD.
    localparam int FRAME_NIBBLES = ETHER_HEADER_NIBBLES + IP_HEADER_NIBBLES +
        UDP_HEADER_NIBBLES + DATA_NIBBLES + FCS_NIBBLES;

    // The number of write cycles to wait after sending after writing data to
    // the PHY. This must be at least 12 bytes worth of time.
    localparam int unsigned GAP_NIBBLES = 24;

    // The Ethernet type for the Ethernet header. This value indicates that
    // IPv4 is used.
    localparam int unsigned ETHER_TYPE = 16'h0800;

    // The IP version to use.
    localparam int unsigned IP_VERSION = 4;

    // The IP header length.
    localparam int unsigned IP_IHL = IP_HEADER_BYTES / 4;

    // The IP type of service. This requests high throughput and reliability.
    localparam int unsigned IP_TOS = 8'h0C;

    // The IP fragment identification.
    localparam int unsigned IP_ID = 0;

    // The IP flags.
    localparam int unsigned IP_FLAGS = 0;

    // The IP fragmentation offset.
    localparam int unsigned IP_FRAG_OFFSET = 0;

    // The IP time to live.
    localparam int unsigned IP_TTL = 8'hFF;

    // The IP next level protocol to use. This is the User Datagram Protocol.
    localparam int unsigned IP_PROTOCOL = 8'h11;

    // This structure represents a frame to be sent.
    struct packed {
        EthernetHeader eth_header;
        IPHeader ip_header;
        UDPHeader udp_header;
        logic [8*DATA_BYTES-1:0] data;
        logic [15:0] fcs;
    } frame;

    // Generate the clock signal to transmit on.
    logic phy_clk;
    logic phy_clk_pulse;
    phy_clk_gen #(.DIVIDER(DIVIDER)) phy_clk_gen_0(
        .clk(clk),
        .reset(clk),
        .clear(0),
        .phy_clk(phy_clk),
        .phy_clk_pulse(phy_clk_pulse)
    );

    // Track the previous send value for edge detection
    logic send_prev;
    always_ff @(posedge clk) begin
        if (reset) begin
            // This is set to 1 to prevent accidentally detecting a rising
            // edge.
            send_prev <= 1;
        end else begin
            send_prev <= send;
        end
    end

    // This enum is used to track the progress of a state machine that writes
    // the data to the PHY.
    enum {
        READY,
        CHECKSUM,
        SEND_PREAMBLE_SFD,
        SEND_FRAME,
        WAIT
    } state;

    // The number of bits to contribute to the FCS on each round.
    localparam int unsigned FCS_STEP = 4;

    // The type of the CRC table to generate.
    typedef int unsigned CRCTable [2**FCS_STEP-1:0];

    // Generate a CRC table with 16 entrie. This can then be applied in rounds
    // with a data size FCS_STEP.
    //
    // This is a precomputed table of the CRC values with round sizes of width
    // FCS_STEP bits. These values are applied to a running CRC value with
    //
    // ```
    // crc <- (crc >> FCS_WIDTH) & CRC_TABLE[(crc & step) (2 ** FCS_STEP - 1)]
    // ```
    //
    // where `crc` is the running CRC and `step` is the data to be added to it.
    function CRCTable crc_table();
        // TODO Is this the right polynomial?
        localparam int unsigned POLYNOMIAL = 32'h04C11DB7;
        for (int unsigned i = 0; i < 2 ** FCS_STEP; i++) begin
            int unsigned r = i;
            // Note that j is unused and is simply a loop counter
            for (int j = 0; j < FCS_STEP; j++) begin
                r = (r & 1) ? ((r >> 1) ^ POLYNOMIAL) : (r >> 1);
            end
            crc_table[i] = r;
        end
    endfunction

    // The CRC to use for computing the FCS.
    localparam CRCTable CRC_TABLE = crc_table();

    // This is used as a general purpose counter. Note that this is signed
    // because it is used to count up and down.
    int i;

    // Run the state machine that sends that data to the PHY.
    always_ff @(posedge clk) begin
        if (reset) begin
            frame <= '0;
            i     <= '0;
            ready <= 1;
            state <= READY;
        end else begin
            case (state)
            // Latch the data
            READY: if (!send_prev && send) begin
                // Construct the Ethernet header
                frame.eth_header.dest_mac   <= ip_info.dest_mac;
                frame.eth_header.src_mac    <= ip_info.src_mac;
                frame.eth_header.ether_type <= ETHER_TYPE;
                // Construct the IP header
                frame.ip_header.version         <= IP_VERSION;
                frame.ip_header.ihl             <= IP_IHL;
                frame.ip_header.type_of_service <= IP_TOS;
                frame.ip_header.total_length    <= IP_BYTES;
                frame.ip_header.identification  <= IP_ID;
                frame.ip_header.flags           <= IP_FLAGS;
                frame.ip_header.fragment_offset <= IP_FRAG_OFFSET;
                frame.ip_header.time_to_live    <= IP_TTL;
                frame.ip_header.protocol        <= IP_PROTOCOL;
                frame.ip_header.header_checksum <= '0; // Computed later
                frame.ip_header.src_ip          <= ip_info.src_ip;
                frame.ip_header.dest_ip         <= ip_info.dest_ip;
                // Construct the UDP header
                frame.udp_header.dest_port <= ip_info.dest_port;
                frame.udp_header.length    <= UDP_BYTES;
                frame.udp_header.checksum  <= '0; // Left as 0
                // Add the data to the frame
                frame.data <= data;
                // The CRC starts as all 1's
                frame.fcs <= 32'hFFFFFFFF;
                // Others
                ready <= 0;
                state <= CHECKSUM;
            end
            // Compute some checksums
            CHECKSUM: begin
                // Compute the IP header checksum
                frame.ip_header.header_checksum <= ~(
                    frame.ip_header[144+:16] +
                    frame.ip_header[128+:16] +
                    frame.ip_header[112+:16] +
                    frame.ip_header[ 96+:16] +
                    frame.ip_header[ 80+:16] +
                    frame.ip_header[ 64+:16] +
                    frame.ip_header[ 48+:16] +
                    frame.ip_header[ 32+:16] +
                    frame.ip_header[ 16+:16] +
                    frame.ip_header[  0+:16]);
                // Others
                state <= SEND_PREAMBLE_SFD;
            end
            // Send the preamble and SFD to the PHY
            SEND_PREAMBLE_SFD: if (phy_clk_pulse) begin
                if (i < PREAMBLE_SFD_NIBBLES) begin
                    eth.tx_d <= (i < PREAMBLE_SFD_NIBBLES - 1) ?
                        4'b1010 : 4'b1011;
                    i <= i + 1;
                end else begin
                    i     <= FRAME_NIBBLES - 1;
                    state <= SEND_FRAME;
                end
            end
            // Send the frame to the PHY
            SEND_FRAME: if (phy_clk_pulse) begin
                // Select the current nibble. This selects nibbles according to
                // the following diagram. Suppose there are 3 bytes, their
                // nibble indices are like the following.
                //
                //          23:20    19:16   15:12    11:8      7:4     3:0
                //            <--------+
                //            +------------------------->
                //                             <--------+
                //                             +------------------------->
                //                                             <---------+
                // Index:     4       5        2        3        0       1
                //
                // These are sent from highest index to lowest.
                logic [3:0] nibble = frame[8 * (i >> 1) + 4 * ((~i) & 1)+:4];
                // Note that this loop counts down
                if (i >= 0) begin
                    // Only add the current byte the FCS CRC when the nibble
                    // index is before the start index of the FCS.
                    if (i >= FCS_NIBBLES) begin
                        frame.fcs <= (frame.fcs >> FCS_STEP) &
                            CRC_TABLE[(frame.fcs ^ i) & (2 ** FCS_STEP - 1)];
                    end
                    i        <= i - 1;
                    eth.tx_d <= nibble;
                    // TODO 1's complement the CRC
                end else begin
                    i     <= '0;
                    state <= WAIT;
                end
            end
            // Wait the appropriate time for the Ethernet interframe gap
            WAIT: if (phy_clk_pulse) begin
                if (i < GAP_NIBBLES) begin
                    i <= i + 1;
                end else begin
                    i     <= '0;
                    ready <= 1;
                    state <= READY;
                end
            end
            endcase
        end
    end

endmodule

/// This module is used to generate a clock pulse used to send out the Ethernet
/// data to the PHY. The resulting clock is only held high for 1 clock cycle
/// of the reference clock.
///
/// # Parameters
///
/// *   `DIVIDER` is the clock divider value to generate the new clock. This
///     must be at least 2.
///
/// # Ports
///
/// *   [clk] is the system clock and the reference clock for the division.
/// *   [reset] is the system reset.
/// *   [clear] is a synchronous clear signal that resets the output clocks
///     while it is asserted. The clocks will begin counting when this is
///     deasserted.
/// *   [phy_clk] is the generated UDP clock with as close to 50% duty cycle as
///     possible. The duty cycle is `(DIVIDER // 2)` / DIVIDER where `//` is
///     used to represent floored division. So an even [DIVIDER] will have a
///     duty cycle of 50% and an odd divider will be as close as possible to
///     50%.
/// *   [phy_clk_pulse] has the same rising edge timing as [phy_clk], though
///     it is only held high for one cycle of the generating clock. This is so
///     it can be used in the logic without an edge detector.
module phy_clk_gen #(
    parameter int DIVIDER = 0) (
    input logic clk,
    input logic reset,
    input logic clear,
    output logic phy_clk,
    output logic phy_clk_pulse);

    // Assert that the parameters are appropriate
    initial begin
        if (DIVIDER < 2) begin
            $error("Expected DIVIDER parameter to be at least 2.");
        end
    end

    // These values are used to divide the clock.
    localparam int unsigned COUNTER_MAX  = DIVIDER - 1;
    localparam int unsigned COUNTER_FLIP = DIVIDER / 2;

    // The counted value used to derive the clock
    int unsigned counter;

    // Update the generated clock.
    always_ff @(posedge clk) begin
        if (reset || clear) begin
            phy_clk       <= 0;
            phy_clk_pulse <= '0;
            counter       <= '0;
        end else begin
            phy_clk       <= counter >= COUNTER_FLIP;
            phy_clk_pulse <= counter == COUNTER_FLIP;
            counter       <= counter < COUNTER_MAX ? counter + 1 : '0;
        end
    end

endmodule
