/// This code is translated from https://github.com/meza/curseforge-fingerprint by GPT-o3-mini-high
use std::fs;

pub type Buffer = Vec<u8>;

/// Reads the entire file at `path` into a Buffer.
pub fn get_jar_contents(path: &str) -> Buffer {
    fs::read(path).unwrap_or_else(|_| {
        println!("Failed to load {}", path);
        Vec::new()
    })
}

/// Computes a hash for the given buffer.
pub fn compute_hash(buffer: &Buffer) -> u32 {
    const MULTIPLEX: u32 = 1540483477;
    let normalized_length = compute_normalized_length(buffer);
    let mut num2 = 1 ^ normalized_length;
    let mut num3 = 0;
    let mut num4 = 0;

    for &b in buffer {
        if !is_whitespace_character(b) {
            num3 |= (b as u32) << num4;
            num4 += 8;
            if num4 == 32 {
                let num6 = num3.wrapping_mul(MULTIPLEX);
                let num7 = (num6 ^ (num6 >> 24)).wrapping_mul(MULTIPLEX);
                num2 = num2.wrapping_mul(MULTIPLEX) ^ num7;
                num3 = 0;
                num4 = 0;
            }
        }
    }

    if num4 > 0 {
        num2 = (num2 ^ num3).wrapping_mul(MULTIPLEX);
    }

    let num6 = (num2 ^ (num2 >> 13)).wrapping_mul(MULTIPLEX);
    num6 ^ (num6 >> 15)
}

/// Returns the count of non-whitespace characters in the buffer.
pub fn compute_normalized_length(buffer: &Buffer) -> u32 {
    buffer
        .iter()
        .filter(|&&b| !is_whitespace_character(b))
        .count() as u32
}

/// Checks if a byte is a whitespace character (tab, newline, carriage return, or space).
pub fn is_whitespace_character(b: u8) -> bool {
    matches!(b, 9 | 10 | 13 | 32)
}
