`timescale 1ns / 1ps

/// The transmit part of a UART that can send data over serial.
///
/// # Parameters
///
/// *   `DIVIDER` is the clock divider value to generate a serial clock.
///
/// # Ports
///
/// *   [clk] is the system clock and the reference clock for the division.
/// *   [rst] is the system reset.
/// *   [d] is the byte to transmit. This is latched and sent when [rdy] is
///     high and [send] rises.
/// *   [send] is rising edge active to latch and send the [d].
/// *   [rdy] indicates that the module is ready to receive a [send] signal
///     to latch and and send the [d]. This is held until the next [send]
///     signal.
/// *   [tx] is the serial line to transmit over.
module uart_send #(
    parameter int unsigned DIVIDER = 0) (
    input logic clk,
    input logic rst,
    input logic [7:0] d,
    input logic send,
    output logic rdy,
    output logic tx);

    // Assert that the parameters are appropriate
    initial begin
        if (DIVIDER < 2) begin
            $error("Expected DIVIDER parameter to be at least 2.");
        end
    end

    logic clr;
    logic baud_clk;
    baud_clk_gen #(.DIVIDER(DIVIDER)) baud_clk_gen(
        .clk(clk),
        .rst(rst),
        .clr(clr),
        .baud_clk_tx(baud_clk),
        .baud_clk_rx(/* Not connected */)
    );

    // The 10-bit frame to be sent
    logic [9:0] frame;

    // Track the previous value of send for edge detection
    logic send_prev;
    always_ff @(posedge clk) begin
        if (rst) begin
            // This starts high on a reset to prevent accidentally detecting an
            // edge as soon as the reset is deasserted if the input is high.
            send_prev <= 1;
        end else begin
            send_prev <= send;
        end
    end

    /// The combined index and state tracker for transmitting a byte.
    int i;

    /// The sentinel values that `i` can take that indicate when a byte should
    /// start being sent, when the byte has finished sending, and when the the
    /// system is waiting to latch the next byte.
    localparam int START_I = 0;
    localparam int DONE_I  = 10;
    localparam int WAIT_I  = 11;

    /// The counter for how many [clk] cycles to wait on the stop bit before
    /// moving to the wait state.
    int w;

    /// The number of [clk] cycles to wait on the stop bit before latching the
    /// next values to send.
    localparam int WAIT_COUNT = (3 * DIVIDER) / 4;

    always_ff @(posedge clk) begin
        if (rst) begin
            clr <= 1;
            i   <= WAIT_I;
            rdy <= 1;
            tx  <= 1;
            w   <= WAIT_COUNT;
        // Waiting to latch the input to send
        end else if (i == WAIT_I) begin
            tx <= 1;
            if (!send_prev && send) begin
                clr   <= 0;
                i     <= START_I;
                frame <= {1'b1, d, 1'b0};
                rdy   <= 0;
                w     <= WAIT_COUNT;
            end
        // After sending a byte, wait a bit before sending the next one so
        // that there is enough time for the stop bit to be seen.
        end else if (i == DONE_I) begin
            clr <= 1;
            i   <= w <= 0 ? WAIT_I : i;
            rdy <= w <= 0 ? 1      : 0;
            w   <= w - 1;
        // Send out the bits on the baud clock
        end else if (baud_clk) begin
            tx <= frame[i];
            i  <= i + 1;
        end
    end

endmodule

/// The receive part of a UART that can read data over serial.
///
/// # Parameters
///
/// *   `DIVIDER` is the clock divider value to generate a serial clock.
///
/// # Ports
///
/// *   [clk] is the system clock and the reference clock for the division.
/// *   [reset] is the system reset.
/// *   [rx] is the serial line to read.
/// *   [d] is the byte that was received. This is updated when [rdy] rises and
///     it valid until [rdy] is driven low.
/// *   [rdy] indicates that the module has received a byte and exposed it on
///     the [d] port. When [rdy] rises the data is ready. This is held high for
///     1 clock cycle.
module uart_recv #(
    parameter int unsigned DIVIDER = 0) (
    input logic clk,
    input logic rst,
    input logic rx,
    output logic [7:0] d,
    output logic rdy);

    // Assert that the parameters are appropriate
    initial begin
        if (DIVIDER < 2) begin
            $error("Expected DIVIDER parameter to be at least 2.");
        end
    end

    logic baud_clk;
    logic clr;
    baud_clk_gen #(.DIVIDER(DIVIDER)) baud_clk_gen(
        .clk(clk),
        .rst(rst),
        .clr(clr),
        .baud_clk_tx(/* Not connected */),
        .baud_clk_rx(baud_clk)
    );

    // A temporary variable for storing the byte to be received.
    logic [7:0] recv_byte;

    // The state machine for reading the bits.
    enum {
        WAITING,
        READ_0,
        READ_1,
        READ_2,
        READ_3,
        READ_4,
        READ_5,
        READ_6,
        READ_7,
        READ_8,
        READ_9
    } state;

    // From the [curr_state], read into the [curr_d] bit and transition into
    // [next_state].
    `define ADVANCE_STATE(curr_state, curr_d, next_state) \
        curr_state: if (baud_clk) begin                   \
            curr_d <= rx;                                 \
            state  <= next_state;                         \
        end

    always_ff @(posedge clk) begin
        if (rst) begin
            clr   <= 0;
            d     <= '0;
            rdy   <= 0;
            state <= WAITING;
        end else begin
            case (state)
                WAITING: begin
                    rdy <= 0;
                    clr <= 1;
                    if (~rx) begin
                        state <= READ_0;
                    end
                end
                READ_0: begin
                    clr <= 0;
                    if (baud_clk) begin
                        // Nothing needs to be read because here it is
                        // guaranteed that the [rx] value is 0.
                        state <= READ_1;
                    end
                end
                `ADVANCE_STATE(READ_1, recv_byte[0], READ_2)
                `ADVANCE_STATE(READ_2, recv_byte[1], READ_3)
                `ADVANCE_STATE(READ_3, recv_byte[2], READ_4)
                `ADVANCE_STATE(READ_4, recv_byte[3], READ_5)
                `ADVANCE_STATE(READ_5, recv_byte[4], READ_6)
                `ADVANCE_STATE(READ_6, recv_byte[5], READ_7)
                `ADVANCE_STATE(READ_7, recv_byte[6], READ_8)
                `ADVANCE_STATE(READ_8, recv_byte[7], READ_9)
                READ_9: if (baud_clk) begin
                    if (rx) begin
                        // The byte is only exposed at the output if the [rx]
                        // is high at the end.
                        d   <= recv_byte;
                        rdy <= 1;
                    end
                    state <= WAITING;
                end
            endcase
        end
    end

    `undef ADVANCE_STATE

endmodule

/// This module is used to generate a baudrate clock off of a base clock to
/// transmit over serial. The phase of this clock is related to the time that a
/// reset or clear event occurs. This creates a clock which starts low, and is
/// only held high for 1 input clock cycle, and then is low for the remainder
/// of the baud clock period.
///
///                   One baud clock period
///                       (DIVIDER = 6)
///                 |----------------------|
///                   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _
///     clk         _| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_|
///                   _                       _                        _
///     baud_clk_tx _| |_____________________| |______________________| |______
///                           _                       _                       _
///     baud_clk_rx _________| |_____________________| |_____________________|
///                 ^
///                 This point is either the end of a reset event ([reset]
///                 falls) or the start of a clear event ([clear] rises). This
///                 is the time that the clock starts. The 1 cycle wide pulses
///                 therefore occur in the middle of the clock period.
///
/// There are two advantages to having clocks that follows these
/// specifications.
///
/// 1.  An edge detector is not needed, and logic can simply run when these
///     clocks go high, since they are only high for one cycle of the
///     generating clock.
/// 2.  For the [baud_clk_tx], the pulse occurs at the beginning of the clock
///     period, so it is ideal for transmitting since it has 0 phase delay that
///     needs to be waited for after the clear event.
/// 3.  For the [baud_clk_rx], the pulse occurs in the middle of the clock
///     period with ~50% phase delay. This is ideal for receiving because the
///     pulse occurs in the middle of each bit that is received. This is the
///     best time to sample the bits.
///
/// # Parameters
///
/// *   `DIVIDER` is the clock divider value to generate the new clocks. This
///     must be at least 2.
///
/// # Ports
///
/// *   [clk] is the system clock and the reference clock for the division.
/// *   [rst] is the system reset.
/// *   [clr] is a synchronous clear signal that resets the output clocks
///     while it is asserted. The clocks will begin counting when this is
///     deasserted.
/// *   [baud_clk_tx] is the clock that is generated for transmitting.
/// *   [baud_clk_rx] is the clock that is generated for receiving.
module baud_clk_gen #(
    parameter int unsigned DIVIDER = 0) (
    input logic clk,
    input logic rst,
    input logic clr,
    output logic baud_clk_tx,
    output logic baud_clk_rx);

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
    localparam CounterInt COUNTER_HALF = COUNTER_MAX / 2;

    // The counted value used to derive the clock
    CounterInt counter;

    // Update the generated clock.
    always_ff @(posedge clk) begin
        if (rst || clr || counter >= COUNTER_MAX) begin
            baud_clk_tx <= 0;
            baud_clk_rx <= 0;
            counter     <= '0;
        end else begin
            baud_clk_tx <= counter == COUNTER_ONE;
            baud_clk_rx <= counter == COUNTER_HALF;
            counter     <= counter + 1;
        end
    end

endmodule
