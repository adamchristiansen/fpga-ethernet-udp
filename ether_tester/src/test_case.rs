extern crate rand;
use super::params::Params;

/// A single test case to perform with the FPGA.
pub struct TestCase<'a> {
    /// The test parameters to use.
    pub params: &'a Params,

    /// The data seed.
    pub seed: u8,

    /// The data generator.
    pub gen: u8
}

impl<'a> TestCase<'a> {
    /// Create a new test case from the test parameters.
    ///
    /// # Arguments
    ///
    /// * `params` - The test parameters to create a test with.
    pub fn new(params: &'a Params) -> TestCase {
        TestCase {
            params: params,
            seed: rand::random(),
            gen: rand::random()
        }
    }

    /// The expected value to receive as the payload for the test.
    ///
    /// # Returns
    ///
    /// The expected values as an array.
    pub fn expected(&self) -> Vec<u8> {
        let mut v = vec![];
        if self.params.bytes > 0 {
            v.push(self.seed);
            for i in 1..self.params.bytes {
                let next = v[i - 1] + self.gen;
                v.push(next);
            }
        }
        return v
    }

    /// Convert the object to bytes that can be sent over serial.
    ///
    /// # Returns
    ///
    /// A byte array representation of the struct.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = vec![];
        // Not that this can't be implemented in a more generic way because some of these numbers
        // 48-bit, which does not lend itself well to removing the size parameter.
        Self::append_bytes(&mut bytes, self.params.src_ip.into(), 4);
        Self::append_bytes(&mut bytes, self.params.src_port.into(), 2);
        Self::append_bytes(&mut bytes, self.params.src_mac, 6);
        Self::append_bytes(&mut bytes, self.params.dest_ip.into(), 4);
        Self::append_bytes(&mut bytes, self.params.dest_port.into(), 2);
        Self::append_bytes(&mut bytes, self.params.dest_mac, 6);
        Self::append_bytes(&mut bytes, self.seed.into(), 1);
        Self::append_bytes(&mut bytes, self.gen.into(), 1);
        assert!(bytes.len() == 26);
        return bytes
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
