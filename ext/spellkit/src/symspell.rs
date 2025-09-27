use hashbrown::{HashMap, HashSet};
use std::cmp::Ordering;
use unicode_normalization::UnicodeNormalization;

#[derive(Debug, Clone)]
pub struct WordEntry {
    pub canonical: String,
    pub frequency: u64,
}

#[derive(Debug, Clone)]
pub struct Suggestion {
    pub term: String,
    pub distance: usize,
    pub frequency: u64,
}

impl Suggestion {
    pub fn new(term: String, distance: usize, frequency: u64) -> Self {
        Self {
            term,
            distance,
            frequency,
        }
    }
}

impl Ord for Suggestion {
    fn cmp(&self, other: &Self) -> Ordering {
        self.distance
            .cmp(&other.distance)
            .then_with(|| other.frequency.cmp(&self.frequency))
            .then_with(|| self.term.cmp(&other.term))
    }
}

impl PartialOrd for Suggestion {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for Suggestion {
    fn eq(&self, other: &Self) -> bool {
        self.term == other.term && self.distance == other.distance && self.frequency == other.frequency
    }
}

impl Eq for Suggestion {}

pub struct SymSpell {
    deletes: HashMap<String, HashSet<String>>,
    words: HashMap<String, WordEntry>,
    max_edit_distance: usize,
}

impl SymSpell {
    pub fn new(max_edit_distance: usize) -> Self {
        Self {
            deletes: HashMap::new(),
            words: HashMap::new(),
            max_edit_distance,
        }
    }

    pub fn normalize_word(word: &str) -> String {
        word.nfkd()
            .filter(|c| !c.is_control() && !c.is_whitespace())
            .collect::<String>()
            .to_lowercase()
    }

    pub fn add_word(&mut self, normalized: &str, canonical: &str, frequency: u64) {
        self.words.insert(
            normalized.to_string(),
            WordEntry {
                canonical: canonical.to_string(),
                frequency,
            },
        );

        let deletes = self.get_deletes(normalized, self.max_edit_distance);
        for delete in deletes {
            self.deletes
                .entry(delete)
                .or_insert_with(HashSet::new)
                .insert(normalized.to_string());
        }
    }

    fn get_deletes(&self, word: &str, edit_distance: usize) -> HashSet<String> {
        let mut deletes = HashSet::new();
        if edit_distance == 0 {
            return deletes;
        }

        let mut queue = vec![word.to_string()];
        let mut processed = HashSet::new();

        for _ in 0..edit_distance {
            let mut temp_queue = Vec::new();
            for item in queue {
                if processed.contains(&item) {
                    continue;
                }
                processed.insert(item.clone());

                for delete in self.generate_deletes(&item) {
                    deletes.insert(delete.clone());

                    // Only continue processing non-empty strings to avoid infinite loops
                    if !delete.is_empty() {
                        temp_queue.push(delete);
                    }
                }
            }
            queue = temp_queue;
        }

        deletes
    }

    fn generate_deletes(&self, word: &str) -> Vec<String> {
        let chars: Vec<char> = word.chars().collect();
        let mut deletes = Vec::new();

        for i in 0..chars.len() {
            let mut new_word = String::new();
            for (j, &ch) in chars.iter().enumerate() {
                if j != i {
                    new_word.push(ch);
                }
            }
            deletes.push(new_word);
        }

        deletes
    }

    pub fn contains(&self, word: &str) -> bool {
        let normalized = Self::normalize_word(word);
        self.words.contains_key(&normalized)
    }

    pub fn get_frequency(&self, word: &str) -> Option<u64> {
        let normalized = Self::normalize_word(word);
        self.words.get(&normalized).map(|entry| entry.frequency)
    }

    pub fn suggestions(&self, word: &str, max_suggestions: usize) -> Vec<Suggestion> {
        let normalized = Self::normalize_word(word);
        let mut suggestions = Vec::new();
        let mut seen = HashSet::new();

        if let Some(entry) = self.words.get(&normalized) {
            suggestions.push(Suggestion::new(entry.canonical.clone(), 0, entry.frequency));
            seen.insert(normalized.clone());
        }

        let input_deletes = self.get_deletes(&normalized, self.max_edit_distance);

        for delete in &input_deletes {
            // Check if this delete is itself a dictionary word (important for finding words shorter than input)
            if !seen.contains(delete) {
                if let Some(entry) = self.words.get(delete) {
                    let distance = self.edit_distance(&normalized, delete);
                    if distance <= self.max_edit_distance {
                        suggestions.push(Suggestion::new(entry.canonical.clone(), distance, entry.frequency));
                        seen.insert(delete.clone());
                    }
                }
            }

            // Check the deletes map for candidates
            if let Some(candidates) = self.deletes.get(delete) {
                for candidate in candidates {
                    if seen.contains(candidate) {
                        continue;
                    }

                    let distance = self.edit_distance(&normalized, candidate);
                    if distance <= self.max_edit_distance {
                        if let Some(entry) = self.words.get(candidate) {
                            suggestions.push(Suggestion::new(entry.canonical.clone(), distance, entry.frequency));
                            seen.insert(candidate.clone());
                        }
                    }
                }
            }
        }

        if let Some(candidates) = self.deletes.get(&normalized) {
            for candidate in candidates {
                if seen.contains(candidate) {
                    continue;
                }

                let distance = self.edit_distance(&normalized, candidate);
                if distance <= self.max_edit_distance {
                    if let Some(entry) = self.words.get(candidate) {
                        suggestions.push(Suggestion::new(entry.canonical.clone(), distance, entry.frequency));
                        seen.insert(candidate.clone());
                    }
                }
            }
        }

        suggestions.sort();
        suggestions.truncate(max_suggestions);
        suggestions
    }

    fn edit_distance(&self, s1: &str, s2: &str) -> usize {
        let len1 = s1.chars().count();
        let len2 = s2.chars().count();

        if len1 == 0 {
            return len2;
        }
        if len2 == 0 {
            return len1;
        }

        let s1_chars: Vec<char> = s1.chars().collect();
        let s2_chars: Vec<char> = s2.chars().collect();

        let mut prev_row: Vec<usize> = (0..=len2).collect();
        let mut curr_row = vec![0; len2 + 1];

        for i in 1..=len1 {
            curr_row[0] = i;

            for j in 1..=len2 {
                let cost = if s1_chars[i - 1] == s2_chars[j - 1] {
                    0
                } else {
                    1
                };

                curr_row[j] = std::cmp::min(
                    std::cmp::min(
                        prev_row[j] + 1,      // deletion
                        curr_row[j - 1] + 1   // insertion
                    ),
                    prev_row[j - 1] + cost    // substitution
                );
            }

            std::mem::swap(&mut prev_row, &mut curr_row);
        }

        prev_row[len2]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_edit_distance() {
        let symspell = SymSpell::new(2);
        assert_eq!(symspell.edit_distance("test", "test"), 0);
        assert_eq!(symspell.edit_distance("test", "tests"), 1);
        assert_eq!(symspell.edit_distance("test", "tast"), 1);
        assert_eq!(symspell.edit_distance("test", "toast"), 2);
    }

    #[test]
    fn test_suggestions() {
        let mut symspell = SymSpell::new(2);
        symspell.add_word("hello", "hello", 1000);
        symspell.add_word("hell", "hell", 500);
        symspell.add_word("help", "help", 750);

        let suggestions = symspell.suggestions("helo", 3);
        assert!(!suggestions.is_empty());
        assert_eq!(suggestions[0].term, "hello");
        assert_eq!(suggestions[0].distance, 1);
    }

    #[test]
    fn test_single_character_corrections() {
        let mut symspell = SymSpell::new(1);
        symspell.add_word("a", "a", 10000);
        symspell.add_word("i", "I", 8000);
        symspell.add_word("o", "o", 6000);

        let suggestions = symspell.suggestions("x", 5);
        assert!(!suggestions.is_empty(), "Single-character corrections should work");
        assert!(suggestions.iter().any(|s| s.term == "a"), "Should suggest 'a' for 'x'");

        let suggestions_for_j = symspell.suggestions("j", 5);
        assert!(!suggestions_for_j.is_empty(), "Should find suggestions for 'j'");
        assert!(suggestions_for_j.iter().any(|s| s.term == "I"), "Should suggest canonical 'I' (not 'i')");
    }
}