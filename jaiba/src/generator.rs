use std::io::Read;
use std::sync::OnceLock;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum GeneratorMode {
    Random,
    Passphrase,
    Pin,
    Hex,
}

pub struct GeneratorOptions {
    pub mode: GeneratorMode,
    pub length: usize,
    pub words: usize,
    pub use_upper: bool,
    pub use_digits: bool,
    pub use_symbols: bool,
    pub exclude_ambiguous: bool,
}

pub fn generate(opts: &GeneratorOptions) -> String {
    match opts.mode {
        GeneratorMode::Random => generate_random(opts),
        GeneratorMode::Passphrase => generate_passphrase(opts),
        GeneratorMode::Pin => generate_pin(opts),
        GeneratorMode::Hex => generate_hex(opts),
    }
}

fn generate_random(opts: &GeneratorOptions) -> String {
    let length = opts.length.clamp(4, 128);

    let lower: Vec<char> = if opts.exclude_ambiguous {
        "abcdefghjkmnpqrstuvwxyz".chars().collect()
    } else {
        "abcdefghijklmnopqrstuvwxyz".chars().collect()
    };

    let upper: Vec<char> = if opts.exclude_ambiguous {
        "ABCDEFGHJKMNPQRSTUVWXYZ".chars().collect()
    } else {
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ".chars().collect()
    };

    let digits: Vec<char> = if opts.exclude_ambiguous {
        "23456789".chars().collect()
    } else {
        "0123456789".chars().collect()
    };

    let symbols: Vec<char> = "!@#$%^&*()-_=+[]{};:,.<>?".chars().collect();

    let mut pools: Vec<Vec<char>> = vec![lower.clone()];

    if opts.use_upper {
        pools.push(upper);
    }

    if opts.use_digits {
        pools.push(digits);
    }

    if opts.use_symbols {
        pools.push(symbols);
    }

    let all: Vec<char> = pools.iter().flatten().copied().collect();

    if all.is_empty() {
        return String::new();
    }

    let mut out: Vec<char> = Vec::with_capacity(length);

    // Guarantee at least one character from each enabled pool when possible.
    if length >= pools.len() {
        for pool in &pools {
            out.push(pool[random_below(pool.len())]);
        }
    }

    while out.len() < length {
        out.push(all[random_below(all.len())]);
    }

    shuffle(&mut out);

    out.into_iter().collect()
}

fn generate_passphrase(opts: &GeneratorOptions) -> String {
    let word_count = opts.words.clamp(1, 20);
    let dict = dictionary_words();

    let mut parts: Vec<String> = Vec::with_capacity(word_count);

    for _ in 0..word_count {
        if dict.is_empty() {
            parts.push(random_token());
        } else {
            parts.push(dict[random_below(dict.len())].clone());
        }
    }

    parts.join("-")
}

fn generate_pin(opts: &GeneratorOptions) -> String {
    let length = opts.length.clamp(4, 32);
    let digits: Vec<char> = "0123456789".chars().collect();

    (0..length)
        .map(|_| digits[random_below(digits.len())])
        .collect()
}

fn generate_hex(opts: &GeneratorOptions) -> String {
    let length = opts.length.clamp(8, 128);
    let byte_count = (length + 1) / 2;
    let bytes = random_bytes(byte_count);

    let mut out: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    out.truncate(length);
    out
}

fn random_token() -> String {
    let consonants: Vec<char> = "bcdfghjkmnpqrstvwxz".chars().collect();
    let vowels: Vec<char> = "aeiou".chars().collect();

    let syllables = 2 + random_below(2);
    let mut token = String::with_capacity(8);

    for _ in 0..syllables {
        token.push(consonants[random_below(consonants.len())]);
        token.push(vowels[random_below(vowels.len())]);

        if random_below(2) == 0 {
            token.push(consonants[random_below(consonants.len())]);
        }
    }

    token
}

fn dictionary_words() -> &'static [String] {
    static WORDS: OnceLock<Vec<String>> = OnceLock::new();

    WORDS.get_or_init(|| {
        let paths = [
            "/usr/share/dict/words",
            "/usr/share/dict/cracklib-small",
        ];

        for path in paths {
            if let Ok(text) = std::fs::read_to_string(path) {
                let words: Vec<String> = text
                    .lines()
                    .map(|line| line.trim().to_ascii_lowercase())
                    .filter(|word| {
                        word.len() >= 4
                            && word.len() <= 8
                            && word.chars().all(|c| c.is_ascii_alphabetic())
                    })
                    .collect();

                if words.len() >= 512 {
                    return words;
                }
            }
        }

        Vec::new()
    })
}

fn shuffle(chars: &mut Vec<char>) {
    if chars.len() <= 1 {
        return;
    }

    for i in (1..chars.len()).rev() {
        let j = random_below(i + 1);
        chars.swap(i, j);
    }
}

fn random_below(limit: usize) -> usize {
    if limit <= 1 {
        return 0;
    }

    let max = usize::MAX - (usize::MAX % limit);

    for _ in 0..8 {
        let bytes = random_bytes(std::mem::size_of::<usize>());
        let mut value: usize = 0;

        for byte in bytes {
            value = (value << 8) | byte as usize;
        }

        if value < max {
            return value % limit;
        }
    }

    // Extremely unlikely fallback.
    let bytes = random_bytes(std::mem::size_of::<usize>());
    let mut value: usize = 0;

    for byte in bytes {
        value = (value << 8) | byte as usize;
    }

    value % limit
}

fn random_bytes(count: usize) -> Vec<u8> {
    let mut buf = vec![0u8; count];

    if let Ok(mut file) = std::fs::File::open("/dev/urandom") {
        if file.read_exact(&mut buf).is_ok() {
            return buf;
        }
    }

    // Non-secure fallback only if /dev/urandom is unavailable.
    let mut state = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0x12345678);

    for i in 0..count {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        buf[i] = (state >> 33) as u8;
    }

    buf
}

#[cfg(test)]
mod tests {
    use super::{generate, GeneratorMode, GeneratorOptions};

    fn options(mode: GeneratorMode, length: usize, words: usize) -> GeneratorOptions {
        GeneratorOptions {
            mode,
            length,
            words,
            use_upper: true,
            use_digits: true,
            use_symbols: true,
            exclude_ambiguous: true,
        }
    }

    #[test]
    fn random_respects_length() {
        let out = generate(&options(GeneratorMode::Random, 24, 6));
        assert_eq!(out.len(), 24);
    }

    #[test]
    fn pin_contains_only_digits() {
        let out = generate(&options(GeneratorMode::Pin, 12, 6));
        assert_eq!(out.len(), 12);
        assert!(out.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn hex_contains_only_hex_chars() {
        let out = generate(&options(GeneratorMode::Hex, 32, 6));
        assert_eq!(out.len(), 32);
        assert!(out.chars().all(|c| c.is_ascii_hexdigit()));
    }
}
