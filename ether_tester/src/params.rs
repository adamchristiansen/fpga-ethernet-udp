extern crate ansi_term;
use clap::{App, ArgMatches};
use regex::Regex;
use serial::*;
use std::result::Result;

/// The regex pattern for matching a string of the form
///
/// ```
/// iii.iii.iii.iii:pppp,mm:mm:mm:mm:mm:mm
/// ```
///
/// Where the `i`s are IP address, `p`s are port, and `m`s are MAC address.
const IP_PORT_MAC_REGEX: &str = r"^(\d+)\.(\d+)\.(\d+)\.(\d+):(\d+),([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2})$";

/// The regex pattern for matching a serial port name and a baudrate of the form
///
/// ```
/// port:baud
/// ```
/// where `port` is the name of a port and `baud` is an integer for the baudrate.
const SERIAL_BAUD_REGEX: &str = r"^([^:]+):(\d+)$";

/// The parameters to the program.
pub struct Params {
    /// The number of bytes per test packet.
    pub bytes: usize,

    /// The host IP address.
    pub dest_ip: u32,

    /// The host port.
    pub dest_port: u16,

    /// The host MAC address.
    pub dest_mac: u64,

    /// The number of tests to run.
    pub reps: usize,

    /// The serial port to use.
    pub serial_port: String,

    /// The baudrate of the serial port.
    pub serial_baud: BaudRate,

    /// Indicates whether all results, not just failures, should be shown.
    pub show_all: bool,

    /// The test device IP address.
    pub src_ip: u32,

    /// The test device port.
    pub src_port: u16,

    /// The test device MAC address.
    pub src_mac: u64,
}

impl Params {
    /// Get the parameters passed in through the command line.
    ///
    /// # Returns
    ///
    /// The program parameters or an error message.
    pub fn get() -> Result<Params, String> {
        let yml = load_yaml!("app.yml");
        let matches = App::from_yaml(yml).get_matches();
        // Get the parameters
        let (dest_ip, dest_port, dest_mac) = Self::ip_port_mac(&matches, "dest".to_string())?;
        let (src_ip, src_port, src_mac) = Self::ip_port_mac(&matches, "src".to_string())?;
        let (serial_port, serial_baud) = Self::serial_port_baud(&matches)?;
        return Ok(Params {
            bytes: Self::bytes(&matches)?,
            dest_ip: dest_ip,
            dest_port: dest_port,
            dest_mac: dest_mac,
            reps: Self::reps(&matches)?,
            serial_port: serial_port,
            serial_baud: serial_baud,
            show_all: Self::show_all(&matches)?,
            src_ip: src_ip,
            src_port: src_port,
            src_mac: src_mac
        })
    }

    /// Parse the bytes parameter.
    ///
    /// # Arguments
    ///
    /// * `matches` - The matches from the command line arguments.
    ///
    /// # Returns
    ///
    /// The number of bytes or an error message.
    fn bytes(matches: &ArgMatches) -> Result<usize, String> {
        let v = matches.value_of("bytes").unwrap();
        match v.parse::<usize>() {
            Ok(b) => Ok(b),
            _ => Err(format!("Bad bytes value: {}", v))
        }
    }

    /// Parse an IP address, port, and MAC address in the parameter with the given name.
    ///
    /// # Arguments
    ///
    /// * `matches` - The matches from the command line arguments.
    /// * `name` - The name of the match to parse.
    ///
    /// # Returns
    ///
    /// The IP address, port, and MAC address, or an error message.
    fn ip_port_mac(matches: &ArgMatches, name: String) -> Result<(u32, u16, u64), String> {
        // Get the raw argument string
        let v = matches.value_of(name).unwrap();
        let raw = match v.parse::<String>() {
            Ok(r) => r,
            _ => return Err(format!("Bad IP, port, and MAC value. {}", v))
        };
        // Parse out the IP, port, and MAC address
        let re = Regex::new(IP_PORT_MAC_REGEX).unwrap();
        let captures = match re.captures(&raw) {
            Some(c) => c,
            None => return Err(format!("Bad IP, port, and MAC specification: {}", raw))
        };
        // Build up the IP, port, and MAC
        let ip = {
            let mut temp: u32 = 0;
            for i in 0..4 {
                match captures.get(1 + i).unwrap().as_str().parse::<u32>() {
                    Ok(n) => temp | n << ((3 - i) * 8),
                    _ => return Err("Invalid IP address".to_string())
                };
            }
            temp
        };
        let port = match captures.get(5).unwrap().as_str().parse::<u16>() {
            Ok(p) => p,
            _ => return Err("Bad port number".to_string())
        };
        let mac = {
            let mut temp: u64 = 0;
            for i in 0..6 {
                match u64::from_str_radix(captures.get(6 + i).unwrap().as_str(), 16) {
                    Ok(n) => temp |= n << ((5 - i) * 8),
                    _ => return Err("Invalid MAC address".to_string())
                };
            }
            temp
        };
        return Ok((ip, port, mac))
    }

    /// Parse the number of repetitions.
    ///
    /// # Arguments
    ///
    /// * `matches` - The matches from the command line arguments.
    ///
    /// # Returns
    ///
    /// The number of repetitions or an error message.
    fn reps(matches: &ArgMatches) -> Result<usize, String> {
        let v = matches.value_of("reps").unwrap();
        match v.parse::<usize>() {
            Ok(r) => Ok(r),
            _ => Err(format!("Bad reps value. {}", v))
        }
    }

    /// Parse the serial port and baudrate.
    ///
    /// # Arguments
    ///
    /// * `matches` - The matches from the command line arguments.
    ///
    /// # Returns
    ///
    /// The serial port and baudrate or an error message.
    fn serial_port_baud(matches: &ArgMatches) -> Result<(String, BaudRate), String> {
        // Get the raw argument string
        let v = matches.value_of("serial-port").unwrap();
        let raw = match v.parse::<String>() {
            Ok(r) => r,
            _ => return Err(format!("Bad IP, port, and MAC value. {}", v))
        };
        // Parse out the serial port amd baudrate
        let re = Regex::new(SERIAL_BAUD_REGEX).unwrap();
        let captures = match re.captures(&raw) {
            Some(c) => c,
            None => return Err(format!("Bad serial port and baudrate specification: {}", raw))
        };
        // Get the port name and baud
        let port = captures.get(1).unwrap().as_str().to_string();
        let baud = match captures.get(2).unwrap().as_str().parse::<usize>() {
            Ok(speed) => BaudRate::from_speed(speed),
            _ => return Err("Bad baudrate".to_string())
        };
        return Ok((port, baud))
    }

    /// Parse the show all parameter.
    ///
    /// # Arguments
    ///
    /// * `matches` - The matches from the command line arguments.
    ///
    /// # Returns
    ///
    /// An indicator of whether the result should show all tests.
    fn show_all(matches: &ArgMatches) -> Result<bool, String> {
        Ok(matches.is_present("show-all"))
    }

    /// Get the destination address as a string.
    ///
    /// # Returns
    ///
    /// The destination address as a human-readable string.
    pub fn dest_info(&self) -> String {
        Self::format_info(&self.dest_ip, &self.dest_port, &self.dest_mac)
    }

    /// Get the source address as a string.
    ///
    /// # Returns
    ///
    /// The source address as a human-readable string.
    pub fn src_info(&self) -> String {
        Self::format_info(&self.src_ip, &self.src_port, &self.src_mac)
    }

    /// Format an IP address, port, and MAC address in a human friendly way.
    ///
    /// # Arguments
    ///
    /// * `ip` - The IP address.
    /// * `port` - The port number.
    /// * `mac` - The MAC address.
    ///
    /// # Returns
    ///
    /// A string with the formatted information.
    fn format_info(ip: &u32, port: &u16, mac: &u64) -> String {
        // A function to get the nth byte of d
        //let b = |d, n| ((d >> (8 * n)) & 0xFF);
        let ip_at  = |n| ((ip  >> (8 * n)) & 0xFFu32);
        let mac_at = |n| ((mac >> (8 * n)) & 0xFFu64);
        format!("IP {}.{}.{}.{}, Port {}, MAC {:02x}:{:02}:{:02}:{:02}:{:02}:{:02}",
            ip_at(3), ip_at(2), ip_at(1), ip_at(0),
            port,
            mac_at(5), mac_at(4), mac_at(3), mac_at(2), mac_at(1), mac_at(0))
    }
}
