extern crate ansi_term;
use ansi_term::Colour::{Green, Red};

#[macro_use]
extern crate clap;
use clap::{App, ArgMatches};

extern crate rand;

extern crate serial;
use serial::*;

use std::io::Write;
use std::net::UdpSocket;
use std::result::Result;
use std::time::Duration;

/// The number of data bytes in a test packet.
const DATA_BYTES: usize = 256;

/// The generator used to transform a seed into the next seed.
const GENERATOR: u8 = 87;

/// The parameters passed into the program.
struct Params {
    /// The baud rate to communicate with the device.
    pub baud: BaudRate,

    /// Only show the test failures.
    pub fail_only: bool,

    /// The IP address and port to communicate with the device.
    pub ip: String,

    /// The serial port to connect to the device.
    pub port: String,

    /// The number of repetitions of the test to run.
    pub reps: usize
}

impl Params {
    /// Get the program arguments.
    ///
    /// # Returns
    ///
    /// The parameters if successful, otherwise an error message.
    fn get() -> Result<Params, String> {
        let yml = load_yaml!("app.yml");
        let matches = App::from_yaml(yml).get_matches();
        return Ok(Params {
            baud: Params::get_baud(&matches)?,
            fail_only: Params::get_fail_only(&matches)?,
            ip: Params::get_ip(&matches)?,
            port: Params::get_port(&matches)?,
            reps: Params::get_reps(&matches)?
        })
    }

    /// Get the baud rate from the program arguments.
    ///
    /// # Returns
    ///
    /// The baud rate if successful, otherwise an error message.
    fn get_baud(matches: &ArgMatches) -> Result<BaudRate, String> {
        let v = matches.value_of("baud").unwrap();
        match v.parse::<usize>() {
            Ok(speed) => Ok(BaudRate::from_speed(speed)),
            _ => Err(format!("Bad vaud value: {}", v))
        }
    }

    /// Get the fail only flag from the program arguments.
    ///
    /// # Returns
    ///
    /// The fail-only indicator, otherwise an error message.
    fn get_fail_only(matches: &ArgMatches) -> Result<bool, String> {
        Ok(matches.occurrences_of("fail-only") > 0)
    }

    /// Get the IP address and port name from the program arguments.
    ///
    /// # Returns
    ///
    /// The IP address and port name if successful, otherwise an error message.
    fn get_ip(matches: &ArgMatches) -> Result<String, String> {
        Ok(matches.value_of("ip").unwrap().to_string())
    }

    /// Get the port name from the program arguments.
    ///
    /// # Returns
    ///
    /// The port name if successful, otherwise an error message.
    fn get_port(matches: &ArgMatches) -> Result<String, String> {
        Ok(matches.value_of("port").unwrap().to_string())
    }

    /// Get the test repetitions from the program arguments.
    ///
    /// # Returns
    ///
    /// The test repetitions if successful, otherwise an error message.
    fn get_reps(matches: &ArgMatches) -> Result<usize, String>{
        let v = matches.value_of("reps").unwrap();
        match v.parse::<usize>() {
            Ok(r) => Ok(r),
            _ => Err(format!("Bad reps value. {}", v))
        }
    }
}

/// Runs a single test by writing the seed to the serial port which governs the UDP packet contents
/// that are sent over the socket.
///
/// # Arguments
///
/// * `port` - An initialized serial port to communicate over.
/// * `socket` - An initialized socket to communicate with the system.
/// * `seed` - The seed that is used to generate the data in the packet.
fn udp_test(port: &mut SystemPort, socket: &mut UdpSocket, seed: u8) -> Result<(), String> {
    // Generate the expected sequence from the seed. This is just an array starting with the seed,
    // and every element if the prebious element plus a costant.
    let mut expected = [seed; DATA_BYTES];
    for i in 1..expected.len() {
        expected[i] = expected[i - 1] + GENERATOR;
    }

    // Write the seed
    if let Err(msg) = port.write(&[seed]) {
        return Err(msg.to_string())
    }

    // Read from the socket
    let mut rdata = [0; DATA_BYTES];

    // Check that the data was read
    if let Ok((size, _)) = socket.recv_from(&mut rdata) {
        if size != expected.len() {
            return Err("Did not receive enough data".to_string());
        }
    } else {
        return Err("Error reading socket".to_string());
    }

    // Chech that the read data is correct
    if &rdata[..] != &expected[..] {
        return Err("Data received did not match the expected value".to_string());
    } else {
        return Ok(())
    }
}

fn main() -> std::io::Result<()> {
    // Get the command line parameters.
    let params = match Params::get() {
        Ok(p) => p,
        Err(message) => {
            println!("{}", message);
            std::process::exit(1)
        }
    };

    // Open a new port
    let mut port = serial::open(&params.port)?;
    let _ = port.reconfigure(&|settings| {
        settings.set_baud_rate(params.baud)?;
        settings.set_char_size(Bits8);
        settings.set_parity(ParityNone);
        settings.set_stop_bits(Stop1);
        settings.set_flow_control(FlowNone);
        Ok(())
    });

    // Open a socket
    let mut socket = UdpSocket::bind(params.ip)?;
    socket.set_read_timeout(Some(Duration::new(1, 0)))?;

    // Print the title in a pretty way
    let title = format!("Reps={}", params.reps);
    println!();
    println!("{}", title);
    println!("{}", std::iter::repeat("-").take(title.len()).collect::<String>()); // Underline

    let mut any_failed = false;
    for rep in 0..params.reps {
        let seed = rand::random();
        match udp_test(&mut port, &mut socket, seed) {
            Ok(_) => {
                if !params.fail_only {
                    println!("{}", Green.paint(format!("Passed {}", rep)))
                }
            },
            Err(msg) => {
                any_failed = true;
                println!("{}", Red.paint(format!("Failed {}: {}", rep, msg)))
            }
        }
    }
    if !any_failed && params.fail_only {
        println!("{}", Green.paint("All passed"))
    }

    Ok(())
}
