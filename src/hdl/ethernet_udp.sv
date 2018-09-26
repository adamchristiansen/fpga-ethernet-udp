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
    logic [47:0] dest_mac;
    logic [47:0] src_mac;
    logic [15:0] ether_type;
} MACHeader;

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
    logic [3:0] version;
    logic [3:0] ihl;
    logic [7:0] type_of_service;
    logic [15:0] total_length;
    logic [15:0] identification;
    logic [2:0] flags;
    logic [12:0] fragment_offset;
    logic [7:0] time_to_live;
    logic [7:0] protocol;
    logic [15:0] header_checksum;
    logic [31:0] src_ip;
    logic [31:0] dest_ip;
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
    logic [15:0] src_port;
    logic [15:0] dest_port;
    logic [15:0] length;
    logic [15:0] checksum;
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
    logic [31:0] src_ip;
    logic [47:0] src_mac;
    logic [15:0] src_port;
    logic [31:0] dest_ip;
    logic [47:0] dest_mac;
    logic [15:0] dest_port;
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
    logic mdc;
    logic mdio;
    logic ref_clk;
    logic rstn;
    logic tx_clk;
    logic tx_en;
    logic [3:0] tx_d;

    modport fwd(
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
/// # Notes
///
/// *   Make sure that the [eth.tx_clk] input is constrained as a 25 MHz
///     clock.
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
/// *   [POWER_UP_CYCLES] is the number of clock cycles to wait at power up
///     before the PHY is ready. This must be at least 167 ms worth of time.
///     The default value is set appropriately for a 100 MHz [clk]. Setting
///     this to 0 or a negative number disables the wait at powerup, but the
///     PHY will not be initialized properly. Disabling the startup check is
///     only really useful in simulation.
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
    parameter int DIVIDER = 0,
    parameter int POWER_UP_CYCLES = 17_000_000) (
    // Standard
    input logic clk,
    input logic reset,
    // Ethernet
    input logic [8*DATA_BYTES-1:0] data,
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
    localparam int unsigned MAC_HEADER_BYTES = 14;
    localparam int unsigned IP_HEADER_BYTES = 20;
    localparam int unsigned UDP_HEADER_BYTES = 8;
    localparam int unsigned FCS_BYTES = 4;

    // The total number of bytes in the UDP packet.
    localparam int unsigned UDP_BYTES = UDP_HEADER_BYTES + DATA_BYTES;

    // The total number of bytes in the IP packet.
    localparam int unsigned IP_BYTES = IP_HEADER_BYTES + UDP_BYTES;

    // The number of bytes that need to be added to frame so that it is
    // a multiple of 4 bytes long. This is added between the data and the FCS.
    localparam int unsigned PAD_BYTES =
        (4 - ((MAC_HEADER_BYTES + IP_BYTES) % 4)) % 4;

    // The number of nibbles in parts of the frame
    localparam int unsigned PREAMBLE_SFD_NIBBLES = 2 * PREAMBLE_SFD_BYTES;
    localparam int unsigned MAC_HEADER_NIBBLES = 2 * MAC_HEADER_BYTES;
    localparam int unsigned IP_HEADER_NIBBLES = 2 * IP_HEADER_BYTES;
    localparam int unsigned UDP_HEADER_NIBBLES = 2 * UDP_HEADER_BYTES;
    localparam int unsigned DATA_NIBBLES = 2 * DATA_BYTES;
    localparam int unsigned PAD_NIBBLES = 2 * PAD_BYTES;
    localparam int unsigned FCS_NIBBLES = 2 * FCS_BYTES;

    // The number of nibbles in the frame (not counting the preamble and SFD).
    localparam int unsigned FRAME_NIBBLES = MAC_HEADER_NIBBLES +
        IP_HEADER_NIBBLES + UDP_HEADER_NIBBLES + DATA_NIBBLES + PAD_NIBBLES +
        FCS_NIBBLES;

    // The number of write cycles to wait after sending after writing data to
    // the PHY. This must be at least 12 bytes worth of time.
    localparam int unsigned GAP_NIBBLES = 40;

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

    // The number of bits to contribute to the FCS on each round.
    localparam int unsigned FCS_STEP = 4;

    // This structure represents a frame to be sent. The padding bytes are
    // added to the data section of the packet.
    struct packed {
        MACHeader mac_header;
        IPHeader ip_header;
        UDPHeader udp_header;
        logic [8*(DATA_BYTES+PAD_BYTES)-1:0] data;
        logic [31:0] fcs;
    } frame;

    // Generate the clock signal to transmit on.
    logic phy_clk;
    phy_clk_gen #(.DIVIDER(DIVIDER)) phy_clk_gen_0(
        .clk(clk),
        .reset(reset),
        .phy_clk(phy_clk)
    );

    // TODO Can MDC and MDIO be removed?
    // Set up the signals to the PHY
    assign eth.mdc = 0;
    assign eth.mdio = 0;
    assign eth.ref_clk = phy_clk;

    // This enum is used to track the progress of a state machine that writes
    // the data to the PHY.
    enum {
        POWER_UP,
        READY,
        CHECKSUM_1,
        CHECKSUM_2,
        SEND_PREAMBLE_SFD,
        SEND_FRAME,
        WAIT
    } state;

    // Computes one step of the CRC-32 algorithm from the previous CRC value.
    //
    // # Arguments
    //
    // * [crc] is the previous CRC value.
    // * [data] is the data to contribute to the CRC.
    //
    // # Returns
    //
    // The next CRC value.
    function logic [31:0] compute_crc(
        input logic [31:0] crc,
        input logic [FCS_STEP-1:0] data);

        localparam int unsigned POLYNOMIAL = 32'h04C11DB7;

        compute_crc = crc;
        for (int j = 0; j < FCS_STEP; j++) begin
            compute_crc = {compute_crc[30:0], 1'b0} ^
                (data[j] == compute_crc[31] ? '0 : POLYNOMIAL);
        end
    endfunction

    // Swaps the nibbles in each byte of a value.
    //
    // # Arguments
    //
    // * [data] is the data to swap nibbles.
    //
    // # Returns
    //
    // The data with swapped nibbles.
    function logic [31:0] swap_nibbles(input logic [31:0] data);
        swap_nibbles[28+:4] = data[24+:4];
        swap_nibbles[24+:4] = data[28+:4];
        swap_nibbles[20+:4] = data[16+:4];
        swap_nibbles[16+:4] = data[20+:4];
        swap_nibbles[12+:4] = data[8+:4];
        swap_nibbles[8+:4]  = data[12+:4];
        swap_nibbles[4+:4]  = data[0+:4];
        swap_nibbles[0+:4]  = data[4+:4];
    endfunction

    // This is used as a general purpose counter. Note that this is signed
    // because it is used to count up and down.
    int i;

    // This value is used as a temporary value in an intermediate step for
    // computing the IP header checksum.
    int unsigned header_checksum_temp;

    // The signal that is latched on the master clock to tell the system to
    // latch the inputs and start sending data. This needs to be held for at
    // least [DIVIDER] clock cycles.
    logic start;

    // The counter that makes sure the start signal is held for the
    // appropriate number of cycles.
    int start_counter;

    // The previous value of the [send] input. This is used for synchronous
    // edge detection.
    logic send_prev;

    // Run some control logic against the master clock.
    always_ff @(posedge clk) begin
        if (reset) begin
            // The previous [send] value is set to 1 to prevent a false
            // positive on a rising edge after a reset.
            send_prev     <= 1;
            start         <= 0;
            start_counter <= '0;
        end else begin
            send_prev <= send;
            // When start_counter is non-zero start is asserted high
            if (start_counter > 0) begin
                start_counter <= start_counter - 1;
            end else if (!start && ready && !send_prev && send) begin
                start <= 1;
                // Although the start signal only needs to be high for
                // a number of clock cycles equal to the divider, just to be
                // safe it is made to twice the divider.
                start_counter <= 2 * DIVIDER;
            end else begin
                start <= 0;
            end
        end
    end

    // Run the state machine that sends that data to the PHY against the
    // transmit clock.
    always_ff @(negedge eth.tx_clk) begin
        if (reset) begin
            eth.rstn  <= 0;
            eth.tx_d  <= '0;
            eth.tx_en <= 0;
            frame     <= '0;
            i         <= '0;
            ready     <= 0;
            state     <= POWER_UP;
        end else begin
            // No longer need to reset
            eth.rstn <= 1;
            // Run the state machine for what to send
            case (state)
            // Wait for the PHY to properly power up
            POWER_UP: if (i < POWER_UP_CYCLES) begin
                i <= i + 1;
            end else begin
                i     <= '0;
                ready <= 1;
                state <= READY;
            end
            // Latch the data
            READY: if (start) begin
                // Construct the Ethernet header
                frame.mac_header.dest_mac   <= ip_info.dest_mac;
                frame.mac_header.src_mac    <= ip_info.src_mac;
                frame.mac_header.ether_type <= ETHER_TYPE;
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
                frame.udp_header.src_port  <= ip_info.src_port;
                frame.udp_header.dest_port <= ip_info.dest_port;
                frame.udp_header.length    <= UDP_BYTES;
                frame.udp_header.checksum  <= '0; // Left as 0
                // Add the data to the frame and zero the padding bytes
                frame.data[8*(DATA_BYTES+PAD_BYTES)-1:8*PAD_BYTES] <= data;
                if (PAD_BYTES > 0) begin
                    frame.data[8*PAD_BYTES-1:0] <= '0;
                end
                // The CRC starts as all 1's
                frame.fcs <= 32'hFFFFFFFF;
                // Others
                ready <= 0;
                state <= CHECKSUM_1;
            end
            // Compute the IP header checksum
            CHECKSUM_1: begin
                header_checksum_temp <=
                    frame.ip_header[144+:16] + // Version, IHL, ToS
                    frame.ip_header[128+:16] + // Total length
                    frame.ip_header[112+:16] + // Identification
                    frame.ip_header[ 96+:16] + // Flags, Fragmentation offset
                    frame.ip_header[ 80+:16] + // TTL, Protocol
                    // frame.ip_header[ 64+:16] + // Header checksum
                    frame.ip_header[ 48+:16] + // Source IP Upper
                    frame.ip_header[ 32+:16] + // Source IP Lower
                    frame.ip_header[ 16+:16] + // Destination IP Upper
                    frame.ip_header[  0+:16];  // Destination IP Lower
                // Others
                state <= CHECKSUM_2;
            end
            CHECKSUM_2: begin
                frame.ip_header.header_checksum <=
                    header_checksum_temp[31:16] + header_checksum_temp[15:0];
                // Others
                i     <= '0;
                state <= SEND_PREAMBLE_SFD;
            end
            // Send the preamble and SFD to the PHY
            SEND_PREAMBLE_SFD: if (i < PREAMBLE_SFD_NIBBLES) begin
                // TODO Note that these are reversed
                eth.tx_d <= (i < PREAMBLE_SFD_NIBBLES - 1) ?
                    4'b0101 : 4'b1101;
                // TODO Should this be enabled here or when the actual
                //      packet data gets sent?
                eth.tx_en <= 1;
                i         <= i + 1;
            end else begin
                i     <= FRAME_NIBBLES - 1;
                state <= SEND_FRAME;
            end
            // Send the frame to the PHY. Note that this loop counts down
            SEND_FRAME: if (i >= 0) begin
                // The transmission must be enabled.
                eth.tx_en <= 1;
                // Select the current nibble. This selects nibbles according
                // to the following diagram. Suppose there are 3 bytes, their
                // nibble indices are like the following.
                //
                //      23:20    19:16   15:12    11:8      7:4     3:0
                //        <--------+
                //        +------------------------->
                //                         <--------+
                //                         +------------------------->
                //                                         <---------+
                // Index: 4       5        2        3        0       1
                // Order: 1       0        3        2        5       4
                //
                // These are sent in order from highest index to lowest. This
                // directive expands to the indexer that will be used for this.
                `define SLICE \
                    8 * (i >> 1) + FCS_STEP * ((~i) & 1)+:FCS_STEP
                // Contribute the nibble to the FCS by manually doing the
                // division
                if (i >= FCS_NIBBLES) begin
                    // Contribute the nibble to the CRC. When i is equal to
                    // FCS_NIBBLES, this is the case where the last nibble is
                    // contributed to the FCS. At this stage, the FCS_NIBBLES
                    // are swapped.
                    if (i == FCS_NIBBLES) begin
                        frame.fcs <= swap_nibbles(compute_crc(
                            frame.fcs, frame[`SLICE]));
                    end else begin
                        frame.fcs <= compute_crc(frame.fcs, frame[`SLICE]);
                    end
                    // Send the nibble
                    eth.tx_d <= frame[`SLICE];
                end else begin
                    // The FCS has been computed and these remaining nibbles
                    // are the nibbles of the FCS.

                    // Get the current nibble and take the one's complement,
                    // then reverse the order of the bits, then send the new
                    // nibble
                    eth.tx_d <= {<<bit{~frame[`SLICE]}};
                    // Assign the reversed bits back to the frame. This is
                    // only really useful for the simulator since these bits
                    // are not read again.
                    frame[`SLICE] <= {<<bit{~frame[`SLICE]}};
                end
                // Others
                i <= i - 1;
                `undef SLICE
            end else begin
                eth.tx_d  <= '0;
                eth.tx_en <= 0;
                i         <= '0;
                state     <= WAIT;
                $display("---- BEGIN FRAME ----");
                $display("%h", frame);
                $display("---- END FRAME ----");
            end
            // Wait the appropriate time for the Ethernet interframe gap
            WAIT: if (i < GAP_NIBBLES) begin
                i <= i + 1;
            end else begin
                i     <= '0;
                ready <= 1;
                state <= READY;
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
/// *   [phy_clk] is the generated UDP clock with as close to 50% duty cycle as
///     possible. The duty cycle is `(DIVIDER // 2)` / DIVIDER where `//` is
///     used to represent floored division. So an even [DIVIDER] will have a
///     duty cycle of 50% and an odd divider will be as close as possible to
///     50%.
module phy_clk_gen #(
    parameter int DIVIDER = 0) (
    input logic clk,
    input logic reset,
    output logic phy_clk);

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
        if (reset) begin
            phy_clk <= 0;
            counter <= '0;
        end else begin
            phy_clk <= counter >= COUNTER_FLIP;
            counter <= counter < COUNTER_MAX ? counter + 1 : '0;
        end
    end

endmodule
