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

/// The parameters the describe the UDP packets to send and the data to be generated for test
/// cases.
struct TestParams {
    /// The IP address of the FPGA.
    pub src_ip: u64,

    /// The MAC address of the FPGA.
    pub src_mac: u64,

    /// The port to use on the FPGA.
    pub src_port: u16,

    /// The IP address of the host machine.
    pub dest_ip: u64,

    /// The MAC address of the host machine.
    pub dest_mac: u64,

    /// The port to use on the host machine.
    pub dest_port: u16,

    /// The seed for generating data.
    pub seed: u8,

    /// The generator for deriving data from the seed.
    pub gen: u8
}

impl TestParams {

    // TODO Better value
    /// The default IP address for the FPGA.
    pub const DEFAULT_SRC_IP:u64 = 0;

    // TODO Better value
    /// The default MAC address for the FPGA.
    pub const DEFAULT_SRC_MAC: u64 = 0;

    // TODO Better value
    /// The default port for the FPGA.
    pub const DEFAULT_SRC_PORT: u16 = 0;

    /// Create a new set of test parameters.
    ///
    /// # Arguments
    ///
    /// * `ip` - The IP address for the host.
    /// * `mac` - The MAC address for the host.
    /// * `port` - The PORT for the host.
    ///
    /// # Returns
    ///
    /// An initialized test params struct.
    pub fn new(ip: u64, mac: u64, port: u16) -> TestParams {
        TestParams {
            src_ip: Self::DEFAULT_SRC_IP,
            src_mac: Self::DEFAULT_SRC_MAC,
            src_port: Self::DEFAULT_SRC_PORT,
            dest_ip: ip,
            dest_mac: mac,
            dest_port: port,
            seed: rand::random(),
            gen: rand::random()
        }
    }

    /// Convert the object to bytes that can be sent over serial.
    ///
    /// # Returns
    ///
    /// A byte array representation of the struct.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = vec![];
        Self::append_bytes(&mut bytes, self.src_ip, 8);
        Self::append_bytes(&mut bytes, self.src_mac, 6);
        Self::append_bytes(&mut bytes, self.src_port.into(), 2);
        Self::append_bytes(&mut bytes, self.dest_ip, 8);
        Self::append_bytes(&mut bytes, self.dest_mac, 6);
        Self::append_bytes(&mut bytes, self.dest_port.into(), 2);
        Self::append_bytes(&mut bytes, self.seed.into(), 1);
        Self::append_bytes(&mut bytes, self.gen.into(), 1);
        assert!(bytes.len() == 34);
        return bytes
    }

    /// The expected value to receive as the payload for the test.
    ///
    /// # Arguments
    ///
    /// * `size` - The size in bytes of the payload.
    ///
    /// # Returns
    ///
    /// The expected values as an array.
    pub fn expected(&self, size: usize) -> Vec<u8> {
        let mut v = vec![];
        v.push(self.seed);
        for i in 1..size {
            let next = v[i - 1] + self.gen;
            v.push(next);
        }
        return v
    }

    /// Add values to a byte vector by deconstructing them. This makes sure that the data is
    /// interpreted in big endian byte order.
    ///
    /// # Arguments
    ///
    /// * `vec` - The vector.
    /// * `data` - Consists of the bytes to be added to the vector.
    /// * `bytes` - The number of lower bytes in the value to add to the vector.
    fn append_bytes(vec: &mut Vec<u8>, data: u64, bytes: u8) {
        // Make sure the number if big endian
        let v = data.to_be();
        for i in (0..bytes).rev() {
            vec.push(((v >> (8 * i)) & 0xFF) as u8);
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
/// * `test_params` - The test parameters to use.
fn udp_test(port: &mut SystemPort, socket: &mut UdpSocket, test_params: &TestParams)
-> Result<(), String> {
    // Generate the expected sequence from the seed. This is just an array starting with the seed,
    // and every element if the prebious element plus a costant.
    let expected = test_params.expected(DATA_BYTES);

    // Write the message to the FPGA to start the test
    if let Err(msg) = port.write(&test_params.to_bytes()) {
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

    // Check that the read data is correct
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

    // Get the test parameters
    // TODO Put the actual values in
    let test_params = TestParams::new(0, 0, 0);

    // Print the title in a pretty way
    let title = format!("Reps={}", params.reps);
    println!();
    println!("{}", title);
    println!("{}", std::iter::repeat("-").take(title.len()).collect::<String>()); // Underline

    let mut any_failed = false;
    for rep in 0..params.reps {
        match udp_test(&mut port, &mut socket, &test_params) {
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
