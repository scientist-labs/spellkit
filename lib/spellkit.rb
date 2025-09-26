require_relative "spellkit/version"

begin
  require "spellkit/spellkit"
rescue LoadError
  require "spellkit.bundle"
end

module SpellKit
  class Error < StandardError; end
  class NotLoadedError < Error; end
  class FileNotFoundError < Error; end
  class InvalidArgumentError < Error; end

  class << self
    def load!(unigrams_path:, symbols_path: nil, cas_path: nil, skus_path: nil,
              species_path: nil, manifest_path: nil, edit_distance: 1,
              frequency_threshold: 10.0, **_options)

      # Validate required path
      raise FileNotFoundError, "Unigrams file not found: #{unigrams_path}" unless File.exist?(unigrams_path.to_s)

      # Validate edit distance
      unless [1, 2].include?(edit_distance)
        raise InvalidArgumentError, "edit_distance must be 1 or 2, got: #{edit_distance}"
      end

      config = {
        "unigrams_path" => unigrams_path.to_s,
        "edit_distance" => edit_distance,
        "frequency_threshold" => frequency_threshold
      }

      config["symbols_path"] = symbols_path.to_s if symbols_path
      config["cas_path"] = cas_path.to_s if cas_path
      config["skus_path"] = skus_path.to_s if skus_path
      config["species_path"] = species_path.to_s if species_path
      config["manifest_path"] = manifest_path.to_s if manifest_path

      load_full(config)
    end
  end
end

# Wrap Rust methods with Ruby-friendly API after extension loads
module SpellKit
  class << self
    # Save original Rust methods
    alias_method :_rust_correct_if_unknown, :correct_if_unknown
    alias_method :_rust_correct_tokens, :correct_tokens

    def correct_if_unknown(word, guard: nil)
      raise InvalidArgumentError, "word cannot be nil" if word.nil?
      raise InvalidArgumentError, "word cannot be empty" if word.to_s.empty?

      use_guard = guard == :domain
      _rust_correct_if_unknown(word, use_guard)
    end

    def correct_tokens(tokens, guard: nil)
      raise InvalidArgumentError, "tokens must be an Array" unless tokens.is_a?(Array)

      use_guard = guard == :domain
      _rust_correct_tokens(tokens, use_guard)
    end
  end
end
