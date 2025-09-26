use hashbrown::HashSet;
use regex::Regex;
use std::sync::OnceLock;

static SYMBOL_REGEX: OnceLock<Regex> = OnceLock::new();
static CAS_REGEX: OnceLock<Regex> = OnceLock::new();

#[derive(Debug, Clone)]
pub struct Guards {
    symbol_pattern: Regex,
    cas_pattern: Regex,
    symbols_set: HashSet<String>,
    cas_set: HashSet<String>,
    skus_set: HashSet<String>,
    species_set: HashSet<String>,
}

impl Guards {
    pub fn new() -> Self {
        // Gene/protein symbols like CDK10, IL-6, BRCA1
        let symbol_pattern = SYMBOL_REGEX
            .get_or_init(|| {
                Regex::new(r"^[A-Z][A-Z0-9]{1,}[\-]?[A-Z0-9]+$").unwrap()
            })
            .clone();

        // CAS registry numbers like 7732-18-5
        let cas_pattern = CAS_REGEX
            .get_or_init(|| {
                Regex::new(r"^\d{2,7}-\d{2}-\d$").unwrap()
            })
            .clone();

        Self {
            symbol_pattern,
            cas_pattern,
            symbols_set: HashSet::new(),
            cas_set: HashSet::new(),
            skus_set: HashSet::new(),
            species_set: HashSet::new(),
        }
    }

    pub fn load_symbols(&mut self, content: &str) {
        for line in content.lines() {
            let trimmed = line.trim();
            if !trimmed.is_empty() && !trimmed.starts_with('#') {
                // Add both original and normalized forms
                self.symbols_set.insert(trimmed.to_string());
                self.symbols_set.insert(trimmed.to_lowercase());

                // Also add variant without hyphen (IL-6 -> IL6)
                if trimmed.contains('-') {
                    let no_hyphen = trimmed.replace('-', "");
                    self.symbols_set.insert(no_hyphen.clone());
                    self.symbols_set.insert(no_hyphen.to_lowercase());
                }
            }
        }
    }

    pub fn load_cas(&mut self, content: &str) {
        for line in content.lines() {
            let trimmed = line.trim();
            if !trimmed.is_empty() && !trimmed.starts_with('#') {
                self.cas_set.insert(trimmed.to_string());
            }
        }
    }

    pub fn load_skus(&mut self, content: &str) {
        for line in content.lines() {
            let trimmed = line.trim();
            if !trimmed.is_empty() && !trimmed.starts_with('#') {
                self.skus_set.insert(trimmed.to_string());
                self.skus_set.insert(trimmed.to_lowercase());
            }
        }
    }

    pub fn load_species(&mut self, content: &str) {
        for line in content.lines() {
            let trimmed = line.trim();
            if !trimmed.is_empty() && !trimmed.starts_with('#') {
                self.species_set.insert(trimmed.to_string());
                self.species_set.insert(trimmed.to_lowercase());
            }
        }
    }

    pub fn is_protected(&self, word: &str) -> bool {
        // Check exact match in sets (case-insensitive)
        let lower = word.to_lowercase();

        if self.symbols_set.contains(word) || self.symbols_set.contains(&lower) {
            return true;
        }

        if self.cas_set.contains(word) {
            return true;
        }

        if self.skus_set.contains(word) || self.skus_set.contains(&lower) {
            return true;
        }

        if self.species_set.contains(word) || self.species_set.contains(&lower) {
            return true;
        }

        // Check regex patterns
        if self.symbol_pattern.is_match(word) {
            return true;
        }

        if self.cas_pattern.is_match(word) {
            return true;
        }

        false
    }

    pub fn is_protected_normalized(&self, word: &str, normalized: &str) -> bool {
        // Check both original and normalized forms
        self.is_protected(word) || self.is_protected(normalized)
    }
}