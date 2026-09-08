require_relative "spellkit/version"
require "uri"
require "net/http"
require "openssl"
require "fileutils"

# Load the compiled Rust extension. Precompiled (platform) gems install it into a
# Ruby-ABI-versioned subdir (lib/spellkit/<major.minor>/spellkit.{so,bundle}) so a
# single fat gem can carry a binary per Ruby version; source/dev builds place it flat
# at lib/spellkit/spellkit.{so,bundle}. Try the versioned path first, fall back to the
# flat one. Resolution goes through $LOAD_PATH (`require`, never `require_relative`)
# because RubyGems installs native extensions outside the gem's lib/ dir.
begin
  RUBY_VERSION =~ /(\d+\.\d+)/
  require "spellkit/#{Regexp.last_match(1)}/spellkit"
rescue LoadError
  require "spellkit/spellkit"
end

require_relative "spellkit/packs"
require_relative "spellkit/lazy_checker"

module SpellKit
  class Error < StandardError; end
  class NotLoadedError < Error; end
  class FileNotFoundError < Error; end
  class InvalidArgumentError < Error; end
  class DownloadError < Error; end

  # Raised when a pack name is not registered - almost always a data gem missing from
  # the Gemfile, since a pack registers itself when its gem loads.
  class UnknownPackError < Error; end

  # Default dictionary: SymSpell English 80k frequency dictionary
  DEFAULT_DICTIONARY_URL = "https://raw.githubusercontent.com/wolfgarbe/SymSpell/master/SymSpell.FrequencyDictionary/en-80k.txt"

  class Configuration
    attr_accessor :dictionary, :protected_path, :protected_patterns, :edit_distance, :frequency_threshold

    def initialize
      @dictionary = DEFAULT_DICTIONARY_URL
      @protected_path = nil
      @protected_patterns = []
      @edit_distance = 1
      @frequency_threshold = 10.0
    end

    def to_h
      {
        dictionary: @dictionary,
        protected_path: @protected_path,
        protected_patterns: @protected_patterns,
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

    def suggestions(word, max = 5)
      default.suggestions(word, max)
    end

    def correct?(word)
      default.correct?(word)
    end

    def correct(word)
      default.correct(word)
    end

    def correct_tokens(tokens)
      default.correct_tokens(tokens)
    end

    def stats
      default.stats
    end

    def healthcheck
      default.healthcheck
    end

    # ----------------------------------------------------------------------------------
    # Dictionary packs
    #
    # SpellKit still bundles no dictionaries. A pack lives in its own gem, registers
    # itself on load (see SpellKit::Packs), and brings the tuning that was measured
    # against its own data. These methods are the mechanism only - SpellKit knows the
    # name of no pack.
    # ----------------------------------------------------------------------------------

    # Configure the DEFAULT checker from a registered pack, so plain SpellKit.correct
    # becomes domain-aware.
    #
    #   SpellKit.enable_dictionary(:general_medical)
    #   SpellKit.enable_dictionary(:general_medical, lazy: true)     # defer the index build
    #   SpellKit.enable_dictionary(:general_medical, edit_distance: 1)
    #   SpellKit.enable_dictionary(dictionary: "my.tsv")             # your own files
    #
    # `lazy: true` is strongly recommended from a Rails initializer - see LazyChecker for
    # why. Eager stays the default so this is non-breaking.
    def enable_dictionary(pack = nil, lazy: false, **options)
      # Resolve eagerly even when lazy, so an unregistered pack (usually a data gem
      # missing from the Gemfile) fails at boot rather than on a user's first search.
      @dictionary_pack = pack.nil? ? nil : Packs.fetch(pack)

      self.default = if lazy
        LazyChecker.new(pack, options)
      else
        load!(**pack_load_options(pack, **options))
      end
    end

    # An INDEPENDENT checker, for running more than one pack at once. Does not touch the
    # default checker.
    def dictionary_checker(pack = nil, lazy: false, **options)
      Packs.fetch(pack) unless pack.nil?
      return LazyChecker.new(pack, options) if lazy

      Checker.new.load!(**pack_load_options(pack, **options))
    end

    # True once the default checker holds a real index.
    def dictionary_loaded?
      checker = @default
      return false if checker.nil?
      return checker.loaded? if checker.is_a?(LazyChecker)

      true
    end

    # Force a deferred load now; no-op when already loaded or configured eagerly.
    def load_dictionary!
      checker = @default
      checker.load_now! if checker.is_a?(LazyChecker)
      checker
    end

    # The pack backing the default checker, or nil when configured from raw files.
    attr_reader :dictionary_pack

    private

    # Internal: resolve a pack name (or a bare options hash) into load! keyword arguments.
    # Private on purpose - see LazyChecker#resolved_options.
    def pack_load_options(pack = nil, **overrides)
      if pack.nil?
        unless overrides.key?(:dictionary)
          raise InvalidArgumentError,
            "Pass a registered pack name or a dictionary: of your own. " \
            "Registered packs: #{Packs.names.inspect}"
        end

        return overrides
      end

      Packs.fetch(pack).load_options(**overrides)
    end
  end
end

# Reopen Rust-defined Checker class to add Ruby wrappers
class SpellKit::Checker
  # Save original Rust methods
  alias_method :_rust_load!, :load!
  alias_method :_rust_suggestions, :suggestions
  alias_method :_rust_correct?, :correct?
  alias_method :_rust_correct, :correct
  alias_method :_rust_correct_tokens, :correct_tokens
  alias_method :_rust_stats, :stats
  alias_method :_rust_healthcheck, :healthcheck

  def load!(dictionary: nil, protected_path: nil, protected_patterns: [],
    edit_distance: 1, frequency_threshold: 10.0,
    skip_urls: false, skip_emails: false, skip_hostnames: false,
    skip_code_patterns: false, skip_numbers: false, **_options)
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

    # Validate frequency_threshold
    unless frequency_threshold.is_a?(Numeric)
      raise SpellKit::InvalidArgumentError, "frequency_threshold must be a number, got: #{frequency_threshold.class}"
    end

    unless frequency_threshold.finite?
      raise SpellKit::InvalidArgumentError, "frequency_threshold must be finite (got NaN or Infinity)"
    end

    if frequency_threshold < 0
      raise SpellKit::InvalidArgumentError, "frequency_threshold must be non-negative, got: #{frequency_threshold}"
    end

    # Build skip patterns from convenience flags
    skip_patterns = build_skip_patterns(
      skip_urls: skip_urls,
      skip_emails: skip_emails,
      skip_hostnames: skip_hostnames,
      skip_code_patterns: skip_code_patterns,
      skip_numbers: skip_numbers
    )

    # Merge skip patterns with user-provided patterns
    all_patterns = skip_patterns + protected_patterns

    config = {
      "dictionary_path" => dictionary_path,
      "edit_distance" => edit_distance,
      "frequency_threshold" => frequency_threshold
    }

    config["protected_path"] = protected_path.to_s if protected_path

    # Convert Ruby Regex objects to hashes with flags for Rust
    if all_patterns.any?
      pattern_objects = all_patterns.map do |pattern|
        if pattern.is_a?(Regexp)
          # Extract flags from Regexp.options bitmask
          options = pattern.options
          {
            "source" => pattern.source,
            "case_insensitive" => (options & Regexp::IGNORECASE) != 0,
            "multiline" => (options & Regexp::MULTILINE) != 0,
            "extended" => (options & Regexp::EXTENDED) != 0
          }
        elsif pattern.is_a?(String)
          # Plain strings default to case-sensitive
          {
            "source" => pattern,
            "case_insensitive" => false,
            "multiline" => false,
            "extended" => false
          }
        else
          raise SpellKit::InvalidArgumentError, "protected_patterns must contain Regexp or String objects"
        end
      end
      config["protected_patterns"] = pattern_objects
    end

    _rust_load!(config)
    self
  end

  def suggestions(word, max = 5)
    raise SpellKit::InvalidArgumentError, "word cannot be nil" if word.nil?
    raise SpellKit::InvalidArgumentError, "word cannot be empty" if word.to_s.empty?

    _rust_suggestions(word, max)
  end

  def correct?(word)
    raise SpellKit::InvalidArgumentError, "word cannot be nil" if word.nil?
    raise SpellKit::InvalidArgumentError, "word cannot be empty" if word.to_s.empty?

    _rust_correct?(word)
  end

  def correct(word)
    raise SpellKit::InvalidArgumentError, "word cannot be nil" if word.nil?
    raise SpellKit::InvalidArgumentError, "word cannot be empty" if word.to_s.empty?

    _rust_correct(word)
  end

  def correct_tokens(tokens)
    raise SpellKit::InvalidArgumentError, "tokens must be an Array" unless tokens.is_a?(Array)

    _rust_correct_tokens(tokens)
  end

  def stats
    _rust_stats
  end

  def healthcheck
    _rust_healthcheck
  end

  private

  def build_skip_patterns(skip_urls:, skip_emails:, skip_hostnames:, skip_code_patterns:, skip_numbers:)
    patterns = []

    # Priority 1: URLs, Emails, Hostnames
    if skip_urls
      # Match http:// or https:// URLs
      patterns << /^https?:\/\/[^\s]+$/i
      # Match www. URLs
      patterns << /^www\.[^\s]+$/i
    end

    if skip_emails
      # Match email addresses: user@domain.com, user+tag@domain.co.uk
      patterns << /^[\w.+-]+@[\w.-]+\.\w+$/i
    end

    if skip_hostnames
      # Match hostnames: example.com, sub.example.com, my-site.co.uk
      # Must have at least one dot and valid TLD
      patterns << /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/i
    end

    # Priority 2: Code patterns
    if skip_code_patterns
      # Match camelCase: starts lowercase, has uppercase (arrayMap, getElementById)
      patterns << /^[a-z]+[A-Z][a-zA-Z0-9]*$/
      # Match PascalCase: starts uppercase, has mixed case (ArrayList, MyClass)
      patterns << /^[A-Z][a-z]+[A-Z][a-zA-Z0-9]*$/
      # Match snake_case: lowercase with underscores (my_function, API_KEY)
      patterns << /^[a-z]+_[a-z0-9_]+$/i
      # Match SCREAMING_SNAKE_CASE: uppercase with underscores
      patterns << /^[A-Z]+_[A-Z0-9_]+$/
      # Match dotted.paths: identifier.identifier (Array.map, config.yml)
      patterns << /^[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_.]*$/
    end

    # Priority 3: Numeric patterns
    if skip_numbers
      # Match version numbers: 1.0, 1.2.3, 1.2.3.4
      patterns << /^\d+\.\d+(\.\d+)?(\.\d+)?$/
      # Match hash/IDs: #123, #4567
      patterns << /^#\d+$/
      # Match measurements with common units
      # Weight: kg, g, mg, lb, oz
      # Distance: km, m, cm, mm, mi, ft, in
      # Data: gb, mb, kb, tb, pb
      # Screen: px, pt, em, rem
      patterns << /^\d+(\.\d+)?(kg|g|mg|lb|oz|km|m|cm|mm|mi|ft|in|gb|mb|kb|tb|pb|px|pt|em|rem)$/i
      # Match standalone numbers at start of word (5kg, 123abc)
      patterns << /^\d/
    end

    patterns
  end

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

    # Download dictionary with timeout and redirect handling
    body = fetch_with_redirects(url, max_redirects: 5, open_timeout: 10, read_timeout: 30)

    # Write to cache
    File.write(cache_file, body)
    cache_file
  rescue URI::InvalidURIError => e
    raise SpellKit::InvalidArgumentError, "Invalid URL: #{url} (#{e.message})"
  rescue Timeout::Error => e
    raise SpellKit::DownloadError, "Download timed out: #{url} (#{e.message})"
  rescue => e
    raise SpellKit::DownloadError, "Failed to download dictionary: #{e.message}"
  end

  def fetch_with_redirects(url, max_redirects: 5, open_timeout: 10, read_timeout: 30, redirect_count: 0)
    raise SpellKit::DownloadError, "Too many redirects (limit: #{max_redirects})" if redirect_count > max_redirects

    uri = URI.parse(url)

    # Configure HTTP client with timeouts and SSL verification
    Net::HTTP.start(uri.host, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: open_timeout,
      read_timeout: read_timeout,
      verify_mode: OpenSSL::SSL::VERIFY_PEER) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPRedirection
        # Follow redirect
        location = response["location"]
        raise SpellKit::DownloadError, "Redirect missing Location header" if location.nil? || location.empty?

        # Handle relative redirects
        redirect_uri = URI.parse(location)
        redirect_url = redirect_uri.relative? ? URI.join(url, location).to_s : location

        fetch_with_redirects(redirect_url, max_redirects: max_redirects, open_timeout: open_timeout,
          read_timeout: read_timeout, redirect_count: redirect_count + 1)
      else
        raise SpellKit::DownloadError, "HTTP #{response.code}: #{response.message} (#{url})"
      end
    end
  rescue Net::OpenTimeout
    raise Timeout::Error, "Connection timeout after #{open_timeout}s: #{url}"
  rescue Net::ReadTimeout
    raise Timeout::Error, "Read timeout after #{read_timeout}s: #{url}"
  rescue SocketError => e
    raise SpellKit::DownloadError, "Network error: #{e.message} (#{url})"
  rescue OpenSSL::SSL::SSLError => e
    raise SpellKit::DownloadError, "SSL verification failed: #{e.message} (#{url})"
  end
end
