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

  class Configuration
    attr_accessor :dictionary, :protected_path, :protected_patterns, :manifest_path, :edit_distance, :frequency_threshold

    def initialize
      @dictionary = DEFAULT_DICTIONARY_URL
      @protected_path = nil
      @protected_patterns = []
      @manifest_path = nil
      @edit_distance = 1
      @frequency_threshold = 10.0
    end

    def to_h
      {
        dictionary: @dictionary,
        protected_path: @protected_path,
        protected_patterns: @protected_patterns,
        manifest_path: @manifest_path,
        edit_distance: @edit_distance,
        frequency_threshold: @frequency_threshold
      }
    end
  end

  class << self
    attr_writer :default

    def configure
      config = Configuration.new
      yield(config)
      @default = Checker.new
      @default.load!(**config.to_h)
      @default
    end

    def default
      @default ||= begin
        checker = Checker.new
        checker.load!(dictionary: DEFAULT_DICTIONARY_URL)
        checker
      end
    end

    # Delegation methods
    def load!(**options)
      @default = Checker.new
      @default.load!(**options)
      @default
    end

    def suggest(word, max = 5)
      default.suggest(word, max)
    end

    def correct_if_unknown(word, guard: nil)
      default.correct_if_unknown(word, guard: guard)
    end

    def correct_tokens(tokens, guard: nil)
      default.correct_tokens(tokens, guard: guard)
    end

    def stats
      default.stats
    end

    def healthcheck
      default.healthcheck
    end
  end
end

# Reopen Rust-defined Checker class to add Ruby wrappers
class SpellKit::Checker
  # Save original Rust methods
  alias_method :_rust_load!, :load!
  alias_method :_rust_suggest, :suggest
  alias_method :_rust_correct_if_unknown, :correct_if_unknown
  alias_method :_rust_correct_tokens, :correct_tokens
  alias_method :_rust_stats, :stats
  alias_method :_rust_healthcheck, :healthcheck

  def load!(dictionary: nil, protected_path: nil, protected_patterns: [],
            manifest_path: nil, edit_distance: 1,
            frequency_threshold: 10.0, **_options)

    # Validate dictionary parameter
    raise SpellKit::InvalidArgumentError, "dictionary parameter is required" if dictionary.nil?

    # Auto-detect URL vs path
    dictionary_path = if dictionary.to_s.start_with?("http://", "https://")
      download_dictionary(dictionary)
    else
      dictionary.to_s
    end

    # Validate file exists
    raise SpellKit::FileNotFoundError, "Dictionary file not found: #{dictionary_path}" unless File.exist?(dictionary_path)

    # Validate edit distance
    unless [1, 2].include?(edit_distance)
      raise SpellKit::InvalidArgumentError, "edit_distance must be 1 or 2, got: #{edit_distance}"
    end

    # Validate protected_patterns is an array
    unless protected_patterns.is_a?(Array)
      raise SpellKit::InvalidArgumentError, "protected_patterns must be an Array"
    end

    config = {
      "dictionary_path" => dictionary_path,
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
          raise SpellKit::InvalidArgumentError, "protected_patterns must contain Regexp or String objects"
        end
      end
      config["protected_patterns"] = pattern_strings
    end

    _rust_load!(config)
    self
  end

  def suggest(word, max = 5)
    raise SpellKit::InvalidArgumentError, "word cannot be nil" if word.nil?
    raise SpellKit::InvalidArgumentError, "word cannot be empty" if word.to_s.empty?

    _rust_suggest(word, max)
  end

  def correct_if_unknown(word, guard: nil)
    raise SpellKit::InvalidArgumentError, "word cannot be nil" if word.nil?
    raise SpellKit::InvalidArgumentError, "word cannot be empty" if word.to_s.empty?

    use_guard = guard == :domain
    _rust_correct_if_unknown(word, use_guard)
  end

  def correct_tokens(tokens, guard: nil)
    raise SpellKit::InvalidArgumentError, "tokens must be an Array" unless tokens.is_a?(Array)

    use_guard = guard == :domain
    _rust_correct_tokens(tokens, use_guard)
  end

  def stats
    _rust_stats
  end

  def healthcheck
    _rust_healthcheck
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
      raise SpellKit::DownloadError, "Failed to download dictionary from #{url}: #{response.code} #{response.message}"
    end

    # Write to cache
    File.write(cache_file, response.body)
    cache_file
  rescue URI::InvalidURIError => e
    raise SpellKit::InvalidArgumentError, "Invalid URL: #{url} (#{e.message})"
  rescue StandardError => e
    raise SpellKit::DownloadError, "Failed to download dictionary: #{e.message}"
  end
end