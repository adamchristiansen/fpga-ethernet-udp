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
    logic unsigned [31:0] src_mac;
    logic unsigned [15:0] src_port;
    logic unsigned [31:0] dest_ip;
    logic unsigned [31:0] dest_mac;
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
/// send variable sized UDP packets using IPv4.
///
/// Since UDP is inherently unsafe (there are plenty of reasons a packet can
/// get dropped), a portion of each packet's payload is (optionally) used as a
/// counter by setting the [USE_COUNTER] parameter on the module. This causes
/// the first 4 bytes of the packet to contain an integer giving the packet a
/// sequence number. Out of order packets can then be received and
/// reconstructed, and dropped packets can be detected. When the [USE_COUNTER]
/// is disabled, the first 4 bytes of the packet are instead used as part of
/// the data, allowing 4 more bytes to be transmitted.
///
/// The [DATA_WIDTH] parameter describes the maximum width (in bytes) that the
/// module should be prepared to transmit through the [data] port. Here is a
/// summary of the most important information sourced from RFCs.
///
/// *   RFC 768: a UDP header is 8 bytes.
/// *   RFC 791: the maximum sized internet header is 60 bytes.
/// *   RFC 791: every host must be able to receive a datagram of at least 576
///     bytes.
///
/// These specifications imply that the safest maximum size of a UDP payload is
/// 576 - 60 - 8 = 508 bytes. This means that the maximum data size that can
/// safely be transmitted is 508 is [USE_COUNTER] is disabled, and 504 if
/// [USE_COUNTER] is enabled.
///
/// The [size] signal is optional, but gives finer control over what is sent.
/// When the [send] signal rises, both [size] and [data] are latched. There are
/// two cases that can happen here.
///
/// 1.  When [size] = 0 or [size] > DATA_WIDTH, the entire [data] register is
///     sent.
/// 2.  When 0 < [size] <= [DATA_WIDTH], the lower [size] bytes in ther [data]
///     register are sent and the rest are ignored.
///
/// # Parameters
///
/// *   [USE_COUNTER] indicates whether a counter should be embedded in the
///     packets to label their order. A value of 0 disables the counter and a
///     value of 1 enables it. All other values are invalid.
///     positive, that number of bytes is used for the counter.
/// *   [DATA_WIDTH] is the width in bytes to be transmitted in the payload of
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
/// *   [size] is an unsigned number that indicates the number of bytes of
/// *   [data] to be sent in the current packet. Set this to 0 to always send
///     the entire [data] register.
/// *   [ready] indicates that the module is ready to accept a [send] signal to
///     transmit more data. This is held high while ready and falls when the
/// *   [send] signal rises.
module ethernet_udp_transmit #(
    parameter int USE_COUNTER = -1,
    parameter int DATA_WIDTH = 0,
    parameter int DIVIDER = 0) (
    // Standard
    input logic clk,
    input logic reset,
    // Ethernet
    input logic [8*DATA_WIDTH-1:0] data,
    EthernetPHY.fwd eth,
    input IPInfo ip_info,
    output logic ready,
    input logic send,
    input logic unsigned [8:0] size);

    // Assert that the parameters are appropriate
    initial begin
        // Check that the USE_COUNTER is set appropriately
        if (USE_COUNTER != 0 && USE_COUNTER != 1) begin
            $error("The USE_COUNTER must be set to 0 or 1");
        end
        // Check that the DATA_WIDTH is set appropriately
        if (DATA_WIDTH <= 0) begin
            $error("The DATA_WIDTH must be set to a positive number.");
        end
        if (USE_COUNTER == 1 && DATA_WIDTH > 504) begin
            $error("The DATA_WIDTH must be less than or equal to 504 when "
                + "USE_COUNTER is set.");
        end else if (DATA_WIDTH > 508) begin
            $error("The DATA_WIDTH must be less than or equal to 508 when "
                + "USE_COUNTER is not set");
        end
        // Check that the clock divider is set appropriately
        if (DIVIDER < 2) begin
            $error("The DIVIDER must be set to at least 2.");
        end
    end

    // Rename some parameters to be more conveniently accessed
    localparam int unsigned DW = DATA_WIDTH;

    // The number of bytes in the IP header.
    localparam int unsigned IP_HEADER_BYTES = 20;

    // The number of bytes in the IP header.
    localparam int unsigned UDP_HEADER_BYTES = 8;

    // The total number of bytes in the IP packet.
    localparam int unsigned IP_TOTAL_BYTES =
        IP_HEADER_BYTES + UDP_HEADER_BYTES + DATA_WIDTH;

    // The total number of bytes in the UDP packet.
    localparam int unsigned UDP_TOTAL_BYTES = UDP_HEADER_BYTES + DATA_WIDTH;

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

    // The IP and UDP headers to use.
    IPHeader ip_header;
    UDPHeader udp_header;

    // Construct the IP header
    always_ff @(posedge clk) begin
        if (reset) begin
            ip_header <= '0;
        end else begin
            ip_header.version         <= IP_VERSION;
            ip_header.ihl             <= IP_IHL;
            ip_header.type_of_service <= IP_TOS;
            ip_header.total_length    <= IP_TOTAL_BYTES;
            ip_header.identification  <= IP_ID;
            ip_header.flags           <= IP_FLAGS;
            ip_header.fragment_offset <= IP_FRAG_OFFSET;
            ip_header.time_to_live    <= IP_TTL;
            ip_header.protocol        <= IP_PROTOCOL;
            ip_header.header_checksum <= '0; // TODO
            ip_header.src_ip          <= ip_info.src_ip;
            ip_header.dest_ip         <= ip_info.dest_ip;
        end
    end

    // Construct the UDP header
    always_ff @(posedge clk) begin
        if (reset) begin
            udp_header <= '0;
        end else begin
            udp_header.src_port  <= ip_info.src_port;
            udp_header.dest_port <= ip_info.dest_port;
            udp_header.length    <= UDP_TOTAL_BYTES;
            udp_header.checksum  <= '0; // TODO
        end
    end

    // TODO Construct the data

    // TODO Compute the IP header checksum

    // TODO Compute the UDP header checksum

    // TODO Send the data to the Ethernet PHY

endmodule

/// This module is used to generate a clock pulse used to send out the Ethernet
/// data to the PHY.
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
/// *   [clk_gen] is the generated UDP clock.
module upd_clock_generator #(
    parameter int DIVIDER = 0) (
    input logic clk,
    input logic reset,
    input logic clear,
    output logic clk_gen);

    // Assert that the parameters are appropriate
    initial begin
        if (DIVIDER < 2) begin
            $error("Expected DIVIDER parameter to be at least 2.");
        end
    end

    // The total width of the unsigned integer needed for the counter.
    localparam int COUNTER_SIZE = $clog2(DIVIDER - 1) + 1;

    // A minimum width integer to use for the clock division counters.
    typedef logic unsigned [COUNTER_SIZE-1:0] CounterInt;

    // These values are used to divide the clock.
    localparam CounterInt COUNTER_MAX  = DIVIDER - 1;
    localparam CounterInt COUNTER_ONE  = 1;

    // The counted value used to derive the clock
    CounterInt counter;

    // Update the generated clock.
    always_ff @(posedge clk) begin
        if (reset || clear || counter >= COUNTER_MAX) begin
            clk_gen <= 0;
            counter <= '0;
        end else begin
            clk_gen <= counter == COUNTER_ONE;
            counter <= counter + 1;
        end
    end

endmodule
