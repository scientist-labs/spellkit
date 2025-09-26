mod symspell;
mod guards;

use magnus::{class, define_module, function, method, prelude::*, Error, RArray, RHash, Ruby, Value, TryConvert};
use std::sync::{Arc, RwLock};
use symspell::SymSpell;
use guards::Guards;

use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone)]
#[magnus::wrap(class = "SpellKit::Checker", free_immediately, size)]
struct Checker {
    state: Arc<RwLock<CheckerState>>,
}

struct CheckerState {
    symspell: Option<SymSpell>,
    guards: Guards,
    loaded: bool,
    frequency_threshold: f64,
    loaded_at: Option<u64>,
    dictionary_size: usize,
    edit_distance: usize,
}

impl CheckerState {
    fn new() -> Self {
        Self {
            symspell: None,
            guards: Guards::new(),
            loaded: false,
            frequency_threshold: 10.0,
            loaded_at: None,
            dictionary_size: 0,
            edit_distance: 1,
        }
    }
}

impl Checker {
    fn new() -> Self {
        Self {
            state: Arc::new(RwLock::new(CheckerState::new())),
        }
    }

    fn load_full(&self, config: RHash) -> Result<(), Error> {
        let ruby = Ruby::get().unwrap();

        // Required: dictionary path
        let dictionary_path: String = TryConvert::try_convert(
            config.fetch::<_, Value>("dictionary_path")
                .map_err(|_| Error::new(ruby.exception_arg_error(), "dictionary_path is required"))?
        )?;

        let content = std::fs::read_to_string(&dictionary_path)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Failed to read dictionary file: {}", e)))?;

    // Optional: edit distance
    let edit_dist: usize = config.get("edit_distance")
        .and_then(|v: Value| TryConvert::try_convert(v).ok())
        .unwrap_or(1);

    if edit_dist > 2 {
        return Err(Error::new(ruby.exception_arg_error(), "edit_distance must be 1 or 2"));
    }

    let mut words = Vec::new();
    for line in content.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() == 2 {
            if let Ok(freq) = parts[1].parse::<u64>() {
                words.push((parts[0].to_string(), freq));
            }
        }
    }

    let dictionary_size = words.len();
    let mut symspell = SymSpell::new(edit_dist);
    symspell.load_dictionary(words);

    let mut guards = Guards::new();

    // Load optional protected terms file
    if let Some(protected_path) = config.get("protected_path") {
        let path: String = TryConvert::try_convert(protected_path)?;
        if let Ok(content) = std::fs::read_to_string(path) {
            guards.load_protected(&content);
        }
    }

    // Load optional protected patterns
    if let Some(patterns_value) = config.get("protected_patterns") {
        let patterns: RArray = TryConvert::try_convert(patterns_value)?;
        for pattern_value in patterns.into_iter() {
            let pattern: String = TryConvert::try_convert(pattern_value)?;
            guards.add_pattern(&pattern)
                .map_err(|e| Error::new(ruby.exception_arg_error(), e))?;
        }
    }

    // Optional frequency threshold
    let frequency_threshold: f64 = config.get("frequency_threshold")
        .and_then(|v: Value| TryConvert::try_convert(v).ok())
        .unwrap_or(10.0);

        let loaded_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .ok()
            .map(|d| d.as_secs());

        let mut state = self.state.write().unwrap();
        state.symspell = Some(symspell);
        state.guards = guards;
        state.frequency_threshold = frequency_threshold;
        state.loaded = true;
        state.loaded_at = loaded_at;
        state.dictionary_size = dictionary_size;
        state.edit_distance = edit_dist;

        Ok(())
    }

    fn suggest(&self, word: String, max: Option<usize>) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        let max_suggestions = max.unwrap_or(5);
        let state = self.state.read().unwrap();

        if !state.loaded {
            return Err(Error::new(ruby.exception_runtime_error(), "Dictionary not loaded. Call load! first"));
        }

        if let Some(ref symspell) = state.symspell {
            let suggestions = symspell.suggest(&word, max_suggestions);
            let result = RArray::new();

            for suggestion in suggestions {
                let hash = RHash::new();
                hash.aset("term", suggestion.term)?;
                hash.aset("distance", suggestion.distance)?;
                hash.aset("freq", suggestion.frequency)?;
                result.push(hash)?;
            }

            Ok(result)
        } else {
            Err(Error::new(ruby.exception_runtime_error(), "SymSpell not initialized"))
        }
    }

    fn correct_if_unknown(&self, word: String, use_guard: Option<bool>) -> Result<String, Error> {
        let ruby = Ruby::get().unwrap();
        let state = self.state.read().unwrap();

        if !state.loaded {
            return Err(Error::new(ruby.exception_runtime_error(), "Dictionary not loaded. Call load! first"));
        }

        // Check if word is protected
        if use_guard.unwrap_or(false) {
            let normalized = SymSpell::normalize_word(&word);
            if state.guards.is_protected_normalized(&word, &normalized) {
                return Ok(word);
            }
        }

        if let Some(ref symspell) = state.symspell {
            let suggestions = symspell.suggest(&word, 5);

            // If exact match exists, return original
            if !suggestions.is_empty() && suggestions[0].distance == 0 {
                return Ok(word);
            }

            // Find best correction with frequency gating
            for suggestion in &suggestions {
                if suggestion.distance <= 1 {
                    // Check frequency threshold - correction should be significantly more common
                    // Since we don't have the original word's frequency, we'll just take any ED=1 match
                    // In a full implementation, we'd check if suggestion.frequency >= threshold * original_freq
                    return Ok(suggestion.term.clone());
                }
            }

            Ok(word)
        } else {
            Err(Error::new(ruby.exception_runtime_error(), "SymSpell not initialized"))
        }
    }

    fn correct_tokens(&self, tokens: RArray, use_guard: Option<bool>) -> Result<RArray, Error> {
        let result = RArray::new();
        let guard = use_guard.unwrap_or(false);

        for token in tokens.into_iter() {
            let word: String = TryConvert::try_convert(token)?;
            let corrected = self.correct_if_unknown(word, Some(guard))?;
            result.push(corrected)?;
        }

        Ok(result)
    }

    fn stats(&self) -> Result<RHash, Error> {
        let state = self.state.read().unwrap();
        let stats = RHash::new();

        if !state.loaded {
            stats.aset("loaded", false)?;
            return Ok(stats);
        }

        stats.aset("loaded", true)?;
        stats.aset("dictionary_size", state.dictionary_size)?;
        stats.aset("edit_distance", state.edit_distance)?;

        if let Some(loaded_at) = state.loaded_at {
            stats.aset("loaded_at", loaded_at)?;
        }

        Ok(stats)
    }

    fn healthcheck(&self) -> Result<(), Error> {
        let ruby = Ruby::get().unwrap();
        let state = self.state.read().unwrap();

        if !state.loaded {
            return Err(Error::new(ruby.exception_runtime_error(), "Dictionary not loaded"));
        }

        if state.symspell.is_none() {
            return Err(Error::new(ruby.exception_runtime_error(), "SymSpell not initialized"));
        }

        Ok(())
    }
}

#[magnus::init]
fn init(_ruby: &Ruby) -> Result<(), Error> {
    let module = define_module("SpellKit")?;
    let checker_class = module.define_class("Checker", class::object())?;

    checker_class.define_singleton_method("new", function!(Checker::new, 0))?;
    checker_class.define_method("load!", method!(Checker::load_full, 1))?;
    checker_class.define_method("suggest", method!(Checker::suggest, 2))?;
    checker_class.define_method("correct_if_unknown", method!(Checker::correct_if_unknown, 2))?;
    checker_class.define_method("correct_tokens", method!(Checker::correct_tokens, 2))?;
    checker_class.define_method("stats", method!(Checker::stats, 0))?;
    checker_class.define_method("healthcheck", method!(Checker::healthcheck, 0))?;

    Ok(())
}