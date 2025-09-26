require_relative "spellkit/version"
require "uri"
require "net/http"
require "fileutils"

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
  class DownloadError < Error; end

  # Default dictionary: SymSpell English 80k frequency dictionary
  DEFAULT_DICTIONARY_URL = "https://raw.githubusercontent.com/wolfgarbe/SymSpell/master/SymSpell.FrequencyDictionary/en-80k.txt"

  class << self
    def load!(dictionary: nil, protected_path: nil, protected_patterns: [],
              manifest_path: nil, edit_distance: 1,
              frequency_threshold: 10.0, **_options)

      # Validate dictionary parameter
      raise InvalidArgumentError, "dictionary parameter is required" if dictionary.nil?

      # Auto-detect URL vs path
      dictionary_path = if dictionary.to_s.start_with?("http://", "https://")
        download_dictionary(dictionary)
      else
        dictionary.to_s
      end

      # Validate file exists
      raise FileNotFoundError, "Dictionary file not found: #{dictionary_path}" unless File.exist?(dictionary_path)

      # Validate edit distance
      unless [1, 2].include?(edit_distance)
        raise InvalidArgumentError, "edit_distance must be 1 or 2, got: #{edit_distance}"
      end

      # Validate protected_patterns is an array
      unless protected_patterns.is_a?(Array)
        raise InvalidArgumentError, "protected_patterns must be an Array"
      end

      config = {
        "dictionary_path" => dictionary_path.to_s,
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

    private

    def download_dictionary(url)
      require "digest"

      # Create cache directory
      cache_dir = File.join(Dir.home, ".cache", "spellkit")
      FileUtils.mkdir_p(cache_dir)

      # Generate cache filename from URL hash
      url_hash = Digest::SHA256.hexdigest(url)[0..15]
      cache_file = File.join(cache_dir, "dict_#{url_hash}.tsv")

      # Return cached file if it exists
      return cache_file if File.exist?(cache_file)

      # Download dictionary
      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)

      unless response.is_a?(Net::HTTPSuccess)
        raise DownloadError, "Failed to download dictionary from #{url}: #{response.code} #{response.message}"
      end

      # Write to cache
      File.write(cache_file, response.body)
      cache_file
    rescue URI::InvalidURIError => e
      raise InvalidArgumentError, "Invalid URL: #{url} (#{e.message})"
    rescue StandardError => e
      raise DownloadError, "Failed to download dictionary: #{e.message}"
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
