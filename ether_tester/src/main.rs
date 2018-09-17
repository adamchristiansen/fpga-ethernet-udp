extern crate ansi_term;
use ansi_term::Colour::{Green, Red};
#[macro_use]
extern crate clap;
extern crate regex;
extern crate serial;
use serial::*;
use std::fmt::Display;
use std::io::Write;
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
        Err(msg) => fatal("bad command line argument", msg)
    };

    // Open a new port
    // TODO Verify port opened and configured successfully
    let mut port = serial::open(&params.serial_port).expect("Could not open port");
    let _ = port.reconfigure(&|settings| {
        settings.set_baud_rate(params.serial_baud)?;
        settings.set_char_size(Bits8);
        settings.set_parity(ParityNone);
        settings.set_stop_bits(Stop1);
        settings.set_flow_control(FlowNone);
        Ok(())
    });

    // TODO Open socket for UDP

    // Print the test information
    println!("Parameters");
    println!("----------");
    println!("{} {}", Green.paint("Source         "), params.src_info());
    println!("{} {}", Green.paint("Destination    "), params.dest_info());
    println!("{} {}", Green.paint("Serial Port    "), params.serial_port);
    println!("{} {}", Green.paint("Serial Baudrate"), params.serial_baud.speed());
    println!();

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
                // TODO
                Ok(())
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
