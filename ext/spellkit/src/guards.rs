use hashbrown::HashSet;
use regex::{Regex, RegexBuilder};

#[derive(Debug, Clone)]
pub struct Guards {
    protected_set: HashSet<String>,
    protected_patterns: Vec<Regex>,
}

impl Guards {
    pub fn new() -> Self {
        Self {
            protected_set: HashSet::new(),
            protected_patterns: Vec::new(),
        }
    }

    pub fn load_protected(&mut self, content: &str) {
        for line in content.lines() {
            let trimmed = line.trim();
            if !trimmed.is_empty() && !trimmed.starts_with('#') {
                self.protected_set.insert(trimmed.to_string());
                self.protected_set.insert(trimmed.to_lowercase());
            }
        }
    }

    pub fn add_pattern(&mut self, pattern: &str) -> Result<(), String> {
        self.add_pattern_with_flags(pattern, false, false, false)
    }

    pub fn add_pattern_with_flags(
        &mut self,
        pattern: &str,
        case_insensitive: bool,
        multiline: bool,
        extended: bool,
    ) -> Result<(), String> {
        match RegexBuilder::new(pattern)
            .case_insensitive(case_insensitive)
            .multi_line(multiline)
            .ignore_whitespace(extended)
            .build()
        {
            Ok(regex) => {
                self.protected_patterns.push(regex);
                Ok(())
            }
            Err(e) => Err(format!("Invalid regex pattern: {}", e)),
        }
    }

    pub fn is_protected(&self, word: &str) -> bool {
        let lower = word.to_lowercase();

        if self.protected_set.contains(word) || self.protected_set.contains(&lower) {
            return true;
        }

        for pattern in &self.protected_patterns {
            if pattern.is_match(word) {
                return true;
            }
        }

        false
    }

    pub fn is_protected_normalized(&self, word: &str, normalized: &str) -> bool {
        self.is_protected(word) || self.is_protected(normalized)
    }
}