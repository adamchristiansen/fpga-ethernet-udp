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
/// *   [reset] is the system reset.
/// *   [data] is the byte to transmit. This is latched and sent when [ready]
///     is high and [send] rises.
/// *   [send] is rising edge active to latch and send the [data].
/// *   [ready] indicates that the module is ready to receive a [send] signal
///     to latch and and send the [data]. This is held until the next [send]
///     signal.
/// *   [tx] is the serial line to transmit over.
module uart_transmit #(
    parameter int unsigned DIVIDER = 0) (
    input logic clk,
    input logic reset,
    input logic [7:0] data,
    input logic send,
    output logic ready,
    output logic tx);

    // Assert that the parameters are appropriate
    initial begin
        if (DIVIDER < 2) begin
            $error("Expected DIVIDER parameter to be at least 2.");
        end
    end

    logic clear;
    logic baud_clk;
    baud_clk_generator #(.DIVIDER(DIVIDER)) baud_clk_generator(
        .clk(clk),
        .reset(reset),
        .clear(clear),
        .baud_clk_tx(baud_clk),
        .baud_clk_rx(/* Not connected */)
    );

    // The 10-bit frame to be sent
    logic [9:0] frame;

    // The state machine for sending the bits.
    enum {
        WAITING,
        SEND_0,
        SEND_1,
        SEND_2,
        SEND_3,
        SEND_4,
        SEND_5,
        SEND_6,
        SEND_7,
        SEND_8,
        SEND_9
    } state;

    // Sends the [curr_data] from the [curr_state] and transitions into
    // [next_state]. Additionally, this updates the `ready` to the value of
    // [next_ready].
    `define ADVANCE_STATE(curr_state, curr_data, next_state, next_ready=0) \
        curr_state: if (baud_clk) begin                                    \
            ready <= next_ready;                                           \
            state <= next_state;                                           \
            tx    <= curr_data;                                            \
        end

    // Track the previous value of send for edge detection
    logic send_prev;
    always_ff @(posedge clk) begin
        if (reset) begin
            // This starts high on a reset to prevent accidentally detecting an
            // edge as soon as the reset is deasserted if the input is high.
            send_prev <= 1;
        end else begin
            send_prev <= send;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            clear <= 1;
            ready <= 1;
            state <= WAITING;
            tx    <= 1;
        end else begin
            case (state)
                WAITING: begin
                    tx    <= 1;
                    if (!send_prev && send) begin
                        clear <= 0;
                        frame <= {1'b1, data, 1'b0};
                        ready <= 0;
                        state <= SEND_0;
                    end else begin
                        clear <= 1;
                    end
                end
                `ADVANCE_STATE(SEND_0, frame[0], SEND_1)
                `ADVANCE_STATE(SEND_1, frame[1], SEND_2)
                `ADVANCE_STATE(SEND_2, frame[2], SEND_3)
                `ADVANCE_STATE(SEND_3, frame[3], SEND_4)
                `ADVANCE_STATE(SEND_4, frame[4], SEND_5)
                `ADVANCE_STATE(SEND_5, frame[5], SEND_6)
                `ADVANCE_STATE(SEND_6, frame[6], SEND_7)
                `ADVANCE_STATE(SEND_7, frame[7], SEND_8)
                `ADVANCE_STATE(SEND_8, frame[8], SEND_9)
                `ADVANCE_STATE(SEND_9, frame[9], WAITING, 1)
            endcase
        end
    end

    `undef ADVANCE_STATE

endmodule

/// The transmit part of a UART that can send data over serial.
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
/// *   [data] is the byte that was received. This is updated when [ready]
///     rises and it valid until [ready] is driven low.
/// *   [ready] indicates that the module has received a byte and exposed it on
///     the [data] port. When [ready] rises the data is ready. This is held
///     high for 1 clock cycle.
module uart_receive #(
    parameter int unsigned DIVIDER = 0) (
    input logic clk,
    input logic reset,
    input logic rx,
    output logic [7:0] data,
    output logic ready);

    // Assert that the parameters are appropriate
    initial begin
        if (DIVIDER < 2) begin
            $error("Expected DIVIDER parameter to be at least 2.");
        end
    end

    logic baud_clk;
    logic clear;
    baud_clk_generator #(.DIVIDER(DIVIDER)) baud_clk_generator(
        .clk(clk),
        .reset(reset),
        .clear(clear),
        .baud_clk_tx(/* Not connected */),
        .baud_clk_rx(baud_clk)
    );

    // A temporary variable for storing the byte to be received.
    logic [7:0] received_byte;

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

    // From the [curr_state], read into the [curr_data] bit and transition into
    // [next_state].
    `define ADVANCE_STATE(curr_state, curr_data, next_state) \
        curr_state: if (baud_clk) begin                      \
            curr_data <= rx;                                 \
            state     <= next_state;                         \
        end

    always_ff @(posedge clk) begin
        if (reset) begin
            clear <= 0;
            data  <= '0;
            ready <= 0;
            state <= WAITING;
        end else begin
            case (state)
                WAITING: begin
                    ready <= 0;
                    clear <= 1;
                    if (~rx) begin
                        state <= READ_0;
                    end
                end
                READ_0: begin
                    clear <= 0;
                    if (baud_clk) begin
                        // Nothing needs to be read because here it is
                        // guaranteed that the [rx] value is 0.
                        state <= READ_1;
                    end
                end
                `ADVANCE_STATE(READ_1, received_byte[0], READ_2)
                `ADVANCE_STATE(READ_2, received_byte[1], READ_3)
                `ADVANCE_STATE(READ_3, received_byte[2], READ_4)
                `ADVANCE_STATE(READ_4, received_byte[3], READ_5)
                `ADVANCE_STATE(READ_5, received_byte[4], READ_6)
                `ADVANCE_STATE(READ_6, received_byte[5], READ_7)
                `ADVANCE_STATE(READ_7, received_byte[6], READ_8)
                `ADVANCE_STATE(READ_8, received_byte[7], READ_9)
                READ_9: if (baud_clk) begin
                    if (rx) begin
                        // The byte is only exposed at the output if the [rx]
                        // is high at the end.
                        data  <= received_byte;
                        ready <= 1;
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
/// *   [reset] is the system reset.
/// *   [clear] is a synchronous clear signal that resets the output clocks
///     while it is asserted. The clocks will begin counting when this is
///     deasserted.
/// *   [baud_clk_tx] is the clock that is generated for transmitting.
/// *   [baud_clk_rx] is the clock that is generated for receiving.
module baud_clk_generator #(
    parameter int unsigned DIVIDER = 0) (
    input logic clk,
    input logic reset,
    input logic clear,
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
        if (reset || clear || counter >= COUNTER_MAX) begin
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
