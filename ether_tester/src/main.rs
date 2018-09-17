extern crate ansi_term;
use ansi_term::Colour::{Green, Red};
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

fn fatal<T: Display, U: Display>(title: T, body: U) -> ! {
    println!("{}: {}: {}", Red.paint("Error"), title, body);
    std::process::exit(1);
}

fn main() {
    // Get the command line arguments
    let params = match Params::get() {
        Ok(p) => p,
        Err(msg) => fatal("Bad command line argument", msg)
    };

    // Print the test parameters
    println!("Parameters");
    println!("----------");
    println!("{} {}", Green.paint("Source         "), Green.paint("(Test Device)"));
    println!("{} {}", Green.paint("  IP           "), params.src_ip_string());
    println!("{} {}", Green.paint("  Port         "), params.src_port);
    println!("{} {}", Green.paint("  Mac          "), params.src_mac_string());
    println!("{} {}", Green.paint("Destination    "), Green.paint("(Host Device)"));
    println!("{} {}", Green.paint("  IP           "), params.dest_ip_string());
    println!("{} {}", Green.paint("  Port         "), params.dest_port);
    println!("{} {}", Green.paint("  Mac          "), params.dest_mac_string());
    println!("{} {}", Green.paint("Serial Port    "), params.serial_port);
    println!("{} {}", Green.paint("Serial Baudrate"), params.serial_baud.speed());
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

    println!("Results");
    println!("-------");
    let mut num_failed: u64 = 0;
    for i in 0..params.reps {
        let test_case = TestCase::new(&params);
        let result: Result<(), String> = port
            // Write the test information over serial
            .write(&test_case.to_bytes())
            .map_err(|err| err.to_string())
            // Read the incoming Ethernet data and compare it to the expected data
            .and_then(|_| {
                // Read the packet
                let mut buf = vec![0; params.bytes];
                match socket.recv_from(&mut buf) {
                    Ok((size, _socket_addr)) => {
                        let expected = test_case.expected();
                        if size != expected.len() {
                            return Err(format!(
                                "Received datagram is {} bytes, expected {} bytes", size,
                                expected.len()))
                        }
                        // The buffer and the expected data are the same size
                        return if buf == expected {
                            Ok(())
                        } else {
                            Err("The datagram did not match the expected value".to_string())
                        }
                    }
                    Err(err) => Err(format!("Could not read socket: {}", err.to_string()))
                }
            });
        // Print output
        match result {
            Ok(_) => if test_case.params.show_all {
                println!("{}", Green.paint(format!("Passed {}", i)));
            },
            Err(msg) => {
                num_failed += 1;
                println!("{}: {}", Red.paint(format!("Failed {}", i)), msg);
            }
        }
    }
    // Print a summary of what happened
    if num_failed > 0 {
        // Print one empty line to separate the summary from the previous failures
        println!();
        println!("{}", Red.paint(format!("Failed {} of {} tests", num_failed, params.reps)));
    // else all tests passed
    } else if !params.show_all {
        println!("{}", Green.paint(format!("Passed all {} tests", params.reps)));
    }
    println!();
}
