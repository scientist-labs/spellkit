mod symspell;

use magnus::{define_module, function, prelude::*, Error, RArray, RHash, Ruby};
use std::cell::RefCell;
use std::sync::{Arc, RwLock};
use symspell::SymSpell;

struct SpellKitState {
    symspell: Option<SymSpell>,
    loaded: bool,
}

impl SpellKitState {
    fn new() -> Self {
        Self {
            symspell: None,
            loaded: false,
        }
    }
}

thread_local! {
    static STATE: RefCell<Arc<RwLock<SpellKitState>>> = RefCell::new(Arc::new(RwLock::new(SpellKitState::new())));
}

fn load_dictionary(ruby: &Ruby, unigrams_path: String, edit_distance: Option<usize>) -> Result<(), Error> {
    let content = std::fs::read_to_string(&unigrams_path)
        .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Failed to read unigrams file: {}", e)))?;

    let edit_dist = edit_distance.unwrap_or(1);
    if edit_dist > 2 {
        return Err(Error::new(ruby.exception_arg_error(), "edit_distance must be 1 or 2"));
    }

    let mut words = Vec::new();
    for line in content.lines() {
        let parts: Vec<&str> = line.split('\t').collect();
        if parts.len() == 2 {
            if let Ok(freq) = parts[1].parse::<u64>() {
                words.push((parts[0].to_string(), freq));
            }
        }
    }

    let mut symspell = SymSpell::new(edit_dist);
    symspell.load_dictionary(words);

    STATE.with(|state| {
        let state_ref = state.borrow();
        let mut state = state_ref.write().unwrap();
        state.symspell = Some(symspell);
        state.loaded = true;
    });

    Ok(())
}

fn suggest(ruby: &Ruby, word: String, max: Option<usize>) -> Result<RArray, Error> {
    let max_suggestions = max.unwrap_or(5);

    STATE.with(|state| {
        let state_ref = state.borrow();
        let state = state_ref.read().unwrap();

        if !state.loaded {
            return Err(Error::new(ruby.exception_runtime_error(), "Dictionary not loaded. Call SpellKit.load! first"));
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
    })
}

fn correct_if_unknown(ruby: &Ruby, word: String) -> Result<String, Error> {
    STATE.with(|state| {
        let state_ref = state.borrow();
        let state = state_ref.read().unwrap();

        if !state.loaded {
            return Err(Error::new(ruby.exception_runtime_error(), "Dictionary not loaded. Call SpellKit.load! first"));
        }

        if let Some(ref symspell) = state.symspell {
            let suggestions = symspell.suggest(&word, 1);

            if !suggestions.is_empty() && suggestions[0].distance == 0 {
                Ok(word)
            } else if !suggestions.is_empty() && suggestions[0].distance <= 1 {
                Ok(suggestions[0].term.clone())
            } else {
                Ok(word)
            }
        } else {
            Err(Error::new(ruby.exception_runtime_error(), "SymSpell not initialized"))
        }
    })
}

#[magnus::init]
fn init(_ruby: &Ruby) -> Result<(), Error> {
    let module = define_module("SpellKit")?;

    module.define_singleton_method("load_dictionary", function!(load_dictionary, 2))?;
    module.define_singleton_method("suggest", function!(suggest, 2))?;
    module.define_singleton_method("correct_if_unknown", function!(correct_if_unknown, 1))?;

    Ok(())
}