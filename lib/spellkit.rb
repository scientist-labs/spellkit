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
    def load!(unigrams_path:, protected_path: nil, protected_patterns: [],
              manifest_path: nil, edit_distance: 1,
              frequency_threshold: 10.0, **_options)

      # Validate required path
      raise FileNotFoundError, "Unigrams file not found: #{unigrams_path}" unless File.exist?(unigrams_path.to_s)

      # Validate edit distance
      unless [1, 2].include?(edit_distance)
        raise InvalidArgumentError, "edit_distance must be 1 or 2, got: #{edit_distance}"
      end

      # Validate protected_patterns is an array
      unless protected_patterns.is_a?(Array)
        raise InvalidArgumentError, "protected_patterns must be an Array"
      end

      config = {
        "unigrams_path" => unigrams_path.to_s,
        "edit_distance" => edit_distance,
        "frequency_threshold" => frequency_threshold
      }

      config["protected_path"] = protected_path.to_s if protected_path
      config["manifest_path"] = manifest_path.to_s if manifest_path

      # Convert Ruby Regex objects to strings for Rust
      if protected_patterns.any?
        pattern_strings = protected_patterns.map do |pattern|
          if pattern.is_a?(Regexp)
            pattern.source
          elsif pattern.is_a?(String)
            pattern
          else
            raise InvalidArgumentError, "protected_patterns must contain Regexp or String objects"
          end
        end
        config["protected_patterns"] = pattern_strings
      end

      load_full(config)
    end
  end
end

# Wrap Rust methods with Ruby-friendly API after extension loads
module SpellKit
  class << self
    def suggest(word, max = 5)
      raise InvalidArgumentError, "word cannot be nil" if word.nil?
      raise InvalidArgumentError, "word cannot be empty" if word.to_s.empty?

      _rust_suggest(word, max)
    end

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

    def stats
      _rust_stats
    end

    def healthcheck
      _rust_healthcheck
    end
  end
end
