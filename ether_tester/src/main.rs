extern crate ansi_term;
use ansi_term::{Colour, Style};
#[macro_use]
extern crate clap;
extern crate regex;
extern crate serial;
use serial::*;
use std::fmt::Display;
use std::io::Write;
use std::net::UdpSocket;
use std::result::Result;

mod params;
mod test_case;
use params::Params;
use test_case::TestCase;

/// Prints a message and then terminates the program.
///
/// # Arguments
///
/// * `title` - The title of the message that is printed first.
/// * `body` - The body of the mesage that is printed second.
fn fatal<T: Display, U: Display>(title: T, body: U) -> ! {
    let style = Style::new().bold().fg(Colour::Red);
    println!("{}: {}: {}", style.paint("Error"), title, body);
    std::process::exit(1);
}

/// Compares two vectors based on length and content, and produces a meaningful error message.
///
/// # Arguments
///
/// * `xs` - The expected values.
/// * `ys` - The actual values.
/// * `ylen` - The number of `y`s to compare.
///
/// # Returns
///
/// Nothing on success and an error message on a failed conparison.
fn verbose_compare(xs: Vec<u8>, ys: Vec<u8>, ylen: usize) -> Result<(), String> {
    let mut xs_iter = xs.iter();
    let mut ys_iter = ys.iter().take(ylen);
    for i in 0.. {
        match (xs_iter.next(), ys_iter.next()) {
            (Some(x), Some(y)) => if x != y {
                return Err(format!("Error in byte {}: {} != {}", i, x, y))
            },
            (Some(x), None) =>
                return Err(format!("Error in byte {}: Expected {:#04X}, got none", i, x)),
            (None, Some(y)) =>
                return Err(format!("Error in byte {}: Expected none, got {:#04X}", i, y)),
            (None, None) => return Ok(()),
        }
    }
    return Ok(())
}

fn main() {
    let title = Style::new().bold().fg(Colour::Blue);
    let heading = Style::new().fg(Colour::Cyan);
    let info = Style::new().fg(Colour::Blue);
    let fail = Style::new().bold().fg(Colour::Red);
    let success = Style::new().bold().fg(Colour::Green);

    // Get the command line arguments
    let params = match Params::get() {
        Ok(p) => p,
        Err(msg) => fatal("Bad command line argument", msg)
    };

    // Print the test parameters
    println!("{}", title.paint("Parameters"));
    println!("{}", title.paint("----------"));
    println!("{} {}", heading.paint("Source         "), info.paint("(Test Device)"));
    println!("{} {}", heading.paint("  IP           "), params.src_ip_string());
    println!("{} {}", heading.paint("  Port         "), params.src_port);
    println!("{} {}", heading.paint("  Mac          "), params.src_mac_string());
    println!("{} {}", heading.paint("Destination    "), info.paint("(Host Device)"));
    println!("{} {}", heading.paint("  IP           "), params.dest_ip_string());
    println!("{} {}", heading.paint("  Port         "), params.dest_port);
    println!("{} {}", heading.paint("  Mac          "), params.dest_mac_string());
    println!("{} {}", heading.paint("Serial Port    "), params.serial_port);
    println!("{} {}", heading.paint("Serial Baudrate"), params.serial_baud.speed());
    println!();

    // Open a new port
    let mut port = match serial::open(&params.serial_port) {
        Ok(p) => p,
        Err(err) => fatal("Could not open serial port", err.to_string())
    };
    match port.reconfigure(&|settings| {
        settings.set_baud_rate(params.serial_baud)?;
        settings.set_char_size(Bits8);
        settings.set_parity(ParityNone);
        settings.set_stop_bits(Stop1);
        settings.set_flow_control(FlowNone);
        Ok(())
    }) {
        Ok(_) => {},
        Err(err) => fatal("Could not change serial settings", err.to_string())
    }

    // Bind a socket to the test system
    let socket_addr = format!("{}:{}", params.src_ip_string(), params.src_port);
    let socket = match UdpSocket::bind(socket_addr) {
        Ok(s) => s,
        Err(err) => fatal("Could not open socket", err.to_string())
    };

    println!("{}", title.paint("Results"));
    println!("{}", title.paint("-------"));
    let mut num_failed: u64 = 0;
    for i in 0..params.reps {
        let test_case = TestCase::new(&params);
        // Run the communication
        let result: Result<(), String> = port
            // Write the test information over serial
            .write(&test_case.to_bytes())
            .map_err(|err| err.to_string())
            // Read the incoming Ethernet data and compare it to the expected data
            .and_then(|_| {
                // Read the packet
                let mut buf = vec![0; params.bytes];
                match socket.recv_from(&mut buf) {
                    Ok((size, _socket_addr)) => verbose_compare(test_case.expected(), buf, size),
                    Err(err) => Err(format!("Could not read socket: {}", err.to_string()))
                }
            });
        // Print output
        match result {
            Ok(_) => if test_case.params.show_all {
                println!("{}", success.paint(format!("Passed {}", i)));
            },
            Err(msg) => {
                num_failed += 1;
                println!("{}: {}", fail.paint(format!("Failed {}", i)), msg);
            }
        }
    }
    // Print a summary of what happened
    if num_failed > 0 {
        // Print one empty line to separate the summary from the previous failures
        println!();
        println!("{}", fail.paint(format!("Failed {} of {} tests", num_failed, params.reps)));
    // else all tests passed
    } else if !params.show_all {
        println!("{}", success.paint(format!("Passed all {} tests", params.reps)));
    }
    println!();
}
