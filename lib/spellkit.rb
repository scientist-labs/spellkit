require_relative "spellkit/version"

begin
  require "spellkit/spellkit"
rescue LoadError
  require "spellkit.bundle"
end

module SpellKit
  class Error < StandardError; end

  class << self
    def load!(unigrams_path:, symbols_path: nil, cas_path: nil, skus_path: nil,
              species_path: nil, edit_distance: 1, frequency_threshold: 10.0, **_options)
      config = {
        "unigrams_path" => unigrams_path.to_s,
        "edit_distance" => edit_distance,
        "frequency_threshold" => frequency_threshold
      }

      config["symbols_path"] = symbols_path.to_s if symbols_path
      config["cas_path"] = cas_path.to_s if cas_path
      config["skus_path"] = skus_path.to_s if skus_path
      config["species_path"] = species_path.to_s if species_path

      load_full(config)
    end

    # Delegate to Rust with proper guard handling
    alias_method :_correct_if_unknown, :correct_if_unknown
    def correct_if_unknown(word, guard: nil)
      use_guard = guard == :domain
      _correct_if_unknown(word, use_guard)
    end

    alias_method :_correct_tokens, :correct_tokens
    def correct_tokens(tokens, guard: nil)
      use_guard = guard == :domain
      _correct_tokens(tokens, use_guard)
    end
  end
end
