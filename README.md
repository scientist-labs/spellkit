<img src="/docs/assets/spellkit-wide.png" alt="spellkit" height="160px">

Fast, safe typo correction for search-term extraction, wrapping the SymSpell algorithm in Rust via Magnus.

SpellKit provides:
- **Fast correction** using SymSpell with configurable edit distance (1 or 2)
- **Term protection** - never alter protected terms using exact matches or regex patterns
- **Hot reload** - update dictionaries without restarting your application
- **Sub-millisecond latency** - p95 < 2µs on small dictionaries
- **Thread-safe** - built with Rust's Arc<RwLock> for safe concurrent access

## Why SpellKit?

### No Runtime Dependencies
SpellKit is a pure Ruby gem with a Rust extension. Just `gem install spellkit` and you're done. No need to install Aspell, Hunspell, or other system packages. This makes deployment simpler and more reliable across different environments.

### Fast Performance
Built on the SymSpell algorithm with Rust, SpellKit delivers:
- **350,000+ operations/second** for spell checking
- **3.7x faster** than Aspell for correctness checks
- **40x faster** than Aspell for generating suggestions
- **p99 latency < 25µs** even under load

See the [Benchmarks](#benchmarks) section for detailed comparisons.

### Production Ready
- Thread-safe concurrent access
- Hot reload dictionaries without restarts
- Instance-based API for multi-domain support
- Comprehensive error handling

## Installation

Add to your Gemfile:

```ruby
gem "spellkit"
```

Or install directly:

```bash
gem install spellkit
```

## Quick Start

SpellKit works with dictionaries from URLs or local files. Try it immediately:

```ruby
require "spellkit"

# Load from URL (downloads and caches automatically)
SpellKit.load!(dictionary: SpellKit::DEFAULT_DICTIONARY_URL)

# Or use a configure block (recommended for Rails)
SpellKit.configure do |config|
  config.dictionary = SpellKit::DEFAULT_DICTIONARY_URL
  config.edit_distance = 1
end

# Or load from local file
# SpellKit.load!(dictionary: "path/to/dictionary.tsv")

# Check if a word is spelled correctly
puts SpellKit.correct?("hello")
# => true

# Get suggestions for a misspelled word
suggestions = SpellKit.suggestions("helllo", 5)
puts suggestions.inspect
# => [{"term"=>"hello", "distance"=>1, "freq"=>...}]

# Correct a typo
corrected = SpellKit.correct("helllo")
puts corrected
# => "hello"

# Batch correction
tokens = %w[helllo wrld ruby teset]
corrected_tokens = SpellKit.correct_tokens(tokens)
puts corrected_tokens.inspect
# => ["hello", "world", "ruby", "test"]

# Check stats
puts SpellKit.stats.inspect
# => {"loaded"=>true, "dictionary_size"=>..., "edit_distance"=>1, "loaded_at"=>...}
```

## Usage

### Basic Correction

```ruby
require "spellkit"

# Load from URL (auto-downloads and caches)
SpellKit.load!(dictionary: "https://example.com/dict.tsv")

# Or from local file
SpellKit.load!(dictionary: "models/dictionary.tsv", edit_distance: 1)

# Check if a word is correct
SpellKit.correct?("hello")
# => true

# Get suggestions
SpellKit.suggestions("lyssis", 5)
# => [{"term"=>"lysis", "distance"=>1, "freq"=>2000}, ...]

# Correct a typo
SpellKit.correct("helllo")
# => "hello"

# Batch correction
tokens = %w[helllo wrld ruby]
SpellKit.correct_tokens(tokens)
# => ["hello", "world", "ruby"]
```

### Term Protection

Protect specific terms from correction using exact matches or regex patterns:

```ruby
# Load with exact-match protected terms
SpellKit.load!(
  dictionary: "models/dictionary.tsv",
  protected_path: "models/protected.txt"   # file with terms to protect
)

# Protect terms matching regex patterns
SpellKit.load!(
  dictionary: "models/dictionary.tsv",
  protected_patterns: [
    /^[A-Z]{3,4}\d+$/,        # gene symbols like CDK10, BRCA1
    /^\d{2,7}-\d{2}-\d$/,     # CAS numbers like 7732-18-5
    /^[A-Z]{2,3}-\d+$/        # SKU patterns like ABC-123
  ]
)

# Or combine both
SpellKit.load!(
  dictionary: "models/dictionary.tsv",
  protected_path: "models/protected.txt",
  protected_patterns: [/^[A-Z]{3,4}\d+$/]
)

# Use guard: :domain to enable protection
SpellKit.correct("CDK10", guard: :domain)
# => "CDK10"  # protected, never changed

# Batch correction with guards
tokens = %w[helllo wrld ABC-123 for CDK10]
SpellKit.correct_tokens(tokens, guard: :domain)
# => ["hello", "world", "ABC-123", "for", "CDK10"]
```

### Multiple Instances

SpellKit supports multiple independent checker instances, useful for different domains or languages:

```ruby
# Create separate instances for different domains
medical_checker = SpellKit::Checker.new
medical_checker.load!(
  dictionary: "models/medical_dictionary.tsv",
  protected_path: "models/medical_terms.txt"
)

legal_checker = SpellKit::Checker.new
legal_checker.load!(
  dictionary: "models/legal_dictionary.tsv",
  protected_path: "models/legal_terms.txt"
)

# Use them independently
medical_checker.suggestions("lyssis", 5)
legal_checker.suggestions("contractt", 5)

# Each maintains its own state
medical_checker.stats  # Shows medical dictionary stats
legal_checker.stats    # Shows legal dictionary stats
```

### Configuration Block

Use the configure block pattern for Rails initializers:

```ruby
SpellKit.configure do |config|
  config.dictionary = "models/dictionary.tsv"
  config.protected_path = "models/protected.txt"
  config.protected_patterns = [/^[A-Z]{3,4}\d+$/]
  config.edit_distance = 1
  config.frequency_threshold = 10.0
end

# This becomes the default instance
SpellKit.suggestions("word", 5)  # Uses configured dictionary
```

## Dictionary Format

### Dictionary (required)

Whitespace-separated file with term and frequency (supports both space and tab delimiters):

```
hello	10000
world	8000
lysis	2000
```

Or space-separated:
```
hello 10000
world 8000
lysis 2000
```

### Protected Terms (optional)

One term per line. Terms are matched case-insensitively:

**protected.txt**
```
# Product codes
ABC-123
XYZ-999

# Technical terms
CDK10
BRCA1

# Brand names
MyBrand
SpecialTerm
```

## Dictionary Sources

SpellKit doesn't bundle dictionaries, but works with several sources:

### Use the Default Dictionary (Recommended)
```ruby
# English 80k word dictionary from SymSpell
SpellKit.load!(dictionary: SpellKit::DEFAULT_DICTIONARY_URL)
```

### Public Dictionary URLs
- **SymSpell English 80k**: `https://raw.githubusercontent.com/wolfgarbe/SymSpell/master/SymSpell.FrequencyDictionary/en-80k.txt`
- **SymSpell English 500k**: `https://raw.githubusercontent.com/wolfgarbe/SymSpell/master/SymSpell.FrequencyDictionary/en-500k.txt`

### Build Your Own
See "Building Dictionaries" section below for creating domain-specific dictionaries.

### Caching
Dictionaries downloaded from URLs are cached in `~/.cache/spellkit/` for faster subsequent loads.

## Configuration

```ruby
SpellKit.load!(
  dictionary: "models/dictionary.tsv",               # required: path or URL
  protected_path: "models/protected.txt",            # optional
  protected_patterns: [/^[A-Z]{3,4}\d+$/],           # optional
  edit_distance: 1,                                  # 1 (default) or 2
  frequency_threshold: 10.0,                         # default: 10.0 (minimum frequency for corrections)

  # Skip pattern filters (all default to false)
  skip_urls: true,                                   # Skip URLs (http://, https://, www.)
  skip_emails: true,                                 # Skip email addresses
  skip_hostnames: true,                              # Skip hostnames (example.com)
  skip_code_patterns: true,                          # Skip code identifiers (camelCase, snake_case, etc.)
  skip_numbers: true                                 # Skip numeric patterns (versions, IDs, measurements)
)
```

### Frequency Threshold

The `frequency_threshold` parameter controls which corrections are accepted by `correct` and `correct_tokens`:

- **For misspelled words** (not in dictionary): Only suggest corrections with frequency ≥ `frequency_threshold`
- **For dictionary words**: Only suggest alternatives with frequency ≥ `frequency_threshold × original_frequency`

This prevents suggesting rare words as corrections for common typos.

**Example:**
```ruby
# With default threshold (10.0), suggest any correction with freq ≥ 10
SpellKit.load!(dictionary: "dict.tsv")
SpellKit.correct("helllo")  # => "hello" (if freq ≥ 10)

# With high threshold (1000.0), only suggest common corrections
SpellKit.load!(dictionary: "dict.tsv", frequency_threshold: 1000.0)
SpellKit.correct("helllo")      # => "hello" (if freq ≥ 1000)
SpellKit.correct("rarword")   # => "rarword" (no correction if freq < 1000)
```

### Skip Patterns

SpellKit can automatically skip certain patterns to avoid "correcting" technical terms, URLs, and other special content. Inspired by Aspell's filter modes, these patterns are applied when `guard: :domain` is enabled.

**Available skip patterns:**

```ruby
SpellKit.load!(
  dictionary: "dict.tsv",
  skip_urls: true,           # Skip URLs: https://example.com, www.example.com
  skip_emails: true,         # Skip emails: user@domain.com, admin+tag@example.com
  skip_hostnames: true,      # Skip hostnames: example.com, api.example.com
  skip_code_patterns: true,  # Skip code: camelCase, snake_case, PascalCase, dotted.paths
  skip_numbers: true         # Skip numbers: 1.2.3, #123, 5kg, 100mb
)

# With skip patterns enabled, technical content is preserved
SpellKit.correct("https://example.com", guard: :domain)  # => "https://example.com"
SpellKit.correct("user@test.com", guard: :domain)        # => "user@test.com"
SpellKit.correct("getElementById", guard: :domain)       # => "getElementById"
SpellKit.correct("version-1.2.3", guard: :domain)        # => "version-1.2.3"

# Regular typos are still corrected
SpellKit.correct("helllo", guard: :domain)               # => "hello"
```

**What each skip pattern matches:**

- **`skip_urls`**: `http://`, `https://`, `www.` URLs
- **`skip_emails`**: Email addresses with standard formats including `+` and `.` in usernames
- **`skip_hostnames`**: Domain names like `example.com`, `api.example.co.uk`
- **`skip_code_patterns`**:
  - `camelCase` (starts lowercase)
  - `PascalCase` (starts uppercase, mixed case)
  - `snake_case` and `SCREAMING_SNAKE_CASE`
  - `dotted.paths` like `Array.map` or `config.yml`
- **`skip_numbers`**:
  - Version numbers: `1.0`, `2.5.3`, `10.15.7.1`
  - Hash/IDs: `#123`, `#4567`
  - Measurements: `5kg`, `2.5m`, `100mb`, `16px`
  - Words starting with digits: `5test`, `123abc`

**Combining with protected_patterns:**

Skip patterns work alongside your custom `protected_patterns`:

```ruby
SpellKit.load!(
  dictionary: "dict.tsv",
  skip_urls: true,                      # Built-in URL skipping
  protected_patterns: [/^CUSTOM-\d+$/]  # Your custom patterns
)

# Both work together
SpellKit.correct("https://example.com", guard: :domain)  # => "https://example.com" (skip_urls)
SpellKit.correct("CUSTOM-123", guard: :domain)           # => "CUSTOM-123" (custom pattern)
```

## API Reference

### `SpellKit.load!(**options)`

Load or reload dictionaries. Thread-safe atomic swap. Accepts URLs (auto-downloads and caches) or local file paths.

**Options:**
- `dictionary:` (required) - URL or path to TSV file with term<TAB>frequency
- `protected_path:` (optional) - Path to file with protected terms (one per line)
- `protected_patterns:` (optional) - Array of Regexp or String patterns to protect
- `edit_distance:` (default: 1) - Maximum edit distance (1 or 2)
- `frequency_threshold:` (default: 10.0) - Minimum frequency ratio for corrections
- `skip_urls:` (default: false) - Skip URLs (http://, https://, www.)
- `skip_emails:` (default: false) - Skip email addresses
- `skip_hostnames:` (default: false) - Skip hostnames (example.com)
- `skip_code_patterns:` (default: false) - Skip code identifiers (camelCase, snake_case, etc.)
- `skip_numbers:` (default: false) - Skip numeric patterns (versions, IDs, measurements)

**Examples:**
```ruby
# From URL (recommended for getting started)
SpellKit.load!(dictionary: SpellKit::DEFAULT_DICTIONARY_URL)

# With skip patterns for technical content
SpellKit.load!(
  dictionary: SpellKit::DEFAULT_DICTIONARY_URL,
  skip_urls: true,
  skip_code_patterns: true
)

# From custom URL
SpellKit.load!(dictionary: "https://example.com/dict.tsv")

# From local file
SpellKit.load!(dictionary: "/path/to/dictionary.tsv")
```

### `SpellKit.correct?(word)`

Check if a word is spelled correctly (exact dictionary match).

**Parameters:**
- `word` (required) - The word to check

**Returns:** Boolean - true if word exists in dictionary, false otherwise

**Performance:** Very fast O(1) HashMap lookup. Use this instead of `suggest()` when you only need to check correctness.

**Example:**
```ruby
SpellKit.correct?("hello")  # => true
SpellKit.correct?("helllo")   # => false
```

### `SpellKit.suggestions(word, max = 5)`

Get ranked suggestions for a word.

**Parameters:**
- `word` (required) - The word to get suggestions for
- `max` (optional, default: 5) - Maximum number of suggestions to return

**Returns:** Array of hashes with `"term"`, `"distance"`, and `"freq"` keys

**Example:**
```ruby
SpellKit.suggestions("helllo", 5)
# => [{"term"=>"hello", "distance"=>1, "freq"=>10000}, ...]
```

### `SpellKit.correct(word, guard:)`

Return corrected word or original if no better match found. Respects `frequency_threshold` configuration.

**Parameters:**
- `word` (required) - The word to correct
- `guard:` (optional) - Set to `:domain` to enable protection checks

**Behavior:**
- Returns original word if it exists in dictionary
- For misspellings, only accepts corrections with frequency ≥ `frequency_threshold`
- Returns original word if no corrections pass the threshold
- When `guard: :domain` is set, protected terms and skip patterns are applied

**Example:**
```ruby
SpellKit.correct("helllo")                  # => "hello"
SpellKit.correct("hello")                   # => "hello" (already correct)
SpellKit.correct("CDK10", guard: :domain)   # => "CDK10" (protected)
```

### `SpellKit.correct_tokens(tokens, guard:)`

Batch correction of an array of tokens. Respects `frequency_threshold` configuration.

**Options:**
- `guard:` - Set to `:domain` to enable protection checks

**Returns:** Array of corrected strings

### `SpellKit.stats`

Get current state statistics.

**Returns:** Hash with:
- `"loaded"` - Boolean
- `"dictionary_size"` - Number of terms
- `"edit_distance"` - Configured edit distance
- `"loaded_at"` - Unix timestamp

### `SpellKit.healthcheck`

Verify system is properly loaded. Raises error if not.

## Term Protection

The `guard: :domain` option enables protection for specific terms:

### Exact Matches
Terms in `protected_path` file are never corrected, even if similar dictionary words exist. Matching is case-insensitive, but original casing is preserved in output.

### Pattern Matching
Terms matching any pattern in `protected_patterns` are protected. Patterns can be:
- Ruby Regexp objects: `/^[A-Z]{3,4}\d+$/`
- Regex strings: `"^[A-Z]{3,4}\\d+$"`

### Examples
```ruby
# Protect specific terms
protected_patterns: [
  /^[A-Z]{3,4}\d+$/,      # Gene symbols: CDK10, BRCA1
  /^\d{2,7}-\d{2}-\d$/,   # CAS numbers: 7732-18-5
  /^[A-Z]{2,3}-\d+$/      # Product codes: ABC-123
]
```

## Rails Integration

```ruby
# config/initializers/spellkit.rb

# Option 1: Use default dictionary (easiest)
SpellKit.configure do |config|
  config.dictionary = SpellKit::DEFAULT_DICTIONARY_URL
end

# Option 2: Use local dictionary with full configuration
SpellKit.configure do |config|
  config.dictionary = Rails.root.join("models/dictionary.tsv")
  config.protected_path = Rails.root.join("models/protected.txt")
  config.protected_patterns = [
    /^[A-Z]{3,4}\d+$/,       # Product codes
    /^\d{2,7}-\d{2}-\d$/     # Reference numbers
  ]
  config.edit_distance = 1
  config.frequency_threshold = 10.0
end

# Option 3: Multiple domain-specific instances
# config/initializers/spellkit.rb
module SpellCheckers
  MEDICAL = SpellKit::Checker.new.tap do |c|
    c.load!(
      dictionary: Rails.root.join("models/medical_dictionary.tsv"),
      protected_path: Rails.root.join("models/medical_terms.txt")
    )
  end

  LEGAL = SpellKit::Checker.new.tap do |c|
    c.load!(
      dictionary: Rails.root.join("models/legal_dictionary.tsv"),
      protected_path: Rails.root.join("models/legal_terms.txt")
    )
  end
end

# In your search preprocessing
class SearchPreprocessor
  def self.correct_query(text)
    tokens = text.downcase.split(/\s+/)
    SpellKit.correct_tokens(tokens, guard: :domain).join(" ")
  end
end
```

## Performance

### SpellKit Standalone (M1 MacBook Pro, Ruby 3.3.0)

**Single Word Suggestions:**
- 18,015 i/s (55.51 μs/i) with max: 1 suggestion
- 17,415 i/s (57.42 μs/i) with max: 5 suggestions
- 17,463 i/s (57.26 μs/i) with max: 10 suggestions

**Correction Performance:**
- `correct`: 8,259 i/s (121.08 μs/i)
- `correct_tokens` (batch): 8,262 i/s (121.04 μs/i)

**Guard Performance:**
- Without guard: 63,932 i/s (15.64 μs/i)
- With guard: 113,490 i/s (8.81 μs/i) - **1.78x faster!**
  *(Guards short-circuit expensive lookups)*

**Latency Distribution (10,000 iterations):**
- p50: 3μs
- p95: 4μs
- p99: 22μs
- max: 192μs

**Raw Throughput:** 385,713 ops/sec

### Comparison with Aspell (M1 MacBook Pro, Ruby 3.3.0)

SpellKit vs Aspell on identical word lists:

**Spell Checking (is word correct?):**
- SpellKit: **3.74x faster** than Aspell

**Generating Suggestions:**
- SpellKit: **40x faster** than Aspell

**Latency at Scale (10,000 iterations):**
- SpellKit p50: 3μs vs Aspell p50: 100μs (~**33x faster**)
- SpellKit p95: 4μs vs Aspell p95: 150μs (~**37x faster**)

### Key Takeaways
1. **Consistent Performance**: p95 and p99 latencies remain low (< 25μs)
2. **Guards are Fast**: Protected term checks improve performance by avoiding dictionary lookups
3. **High Throughput**: Over 385k operations per second
4. **Scales Well**: Minimal performance difference between 1 vs 10 suggestions

## Benchmarks

SpellKit includes comprehensive benchmarks to measure performance and compare with other spell checkers.

### Running Benchmarks

**Performance Benchmark** - Comprehensive SpellKit performance analysis:
```bash
bundle exec ruby benchmark/performance.rb
```

Measures:
- Single word suggestions with varying result limits
- Correction performance on mixed datasets
- Batch correction throughput
- Guard/protection overhead
- Latency distribution (p50, p95, p99)
- Raw throughput (ops/sec)

**Aspell Comparison** - Direct comparison with Aspell:
```bash
# First install Aspell if needed:
# macOS: brew install aspell
# Ubuntu: sudo apt-get install aspell libaspell-dev

bundle exec ruby benchmark/comparison_aspell.rb
```

Compares SpellKit with Aspell on:
- Single word correction performance
- Spell checking (correctness tests)
- Latency distribution at scale

See [benchmark/README.md](benchmark/README.md) for detailed results and analysis.

### Why These Benchmarks?

**SpellKit vs Aspell**: Both provide fuzzy matching and suggestions for misspelled words, but use different algorithms:
- **SpellKit (SymSpell)**: O(1) lookup complexity, optimized for speed with large dictionaries
- **Aspell**: Statistical scoring with phonetic similarity, good for natural language

The comparison shows SpellKit's performance advantage while solving the same problem.

## Building Dictionaries

Create your dictionary from your corpus:

```ruby
# example_builder.rb
require "set"

counts = Hash.new(0)

# Read your corpus
File.foreach("corpus.txt") do |line|
  line.downcase.split(/\W+/).each do |word|
    next if word.length < 3
    counts[word] += 1
  end
end

# Filter by minimum count and write
min_count = 5
File.open("dictionary.tsv", "w") do |f|
  counts.select { |_, count| count >= min_count }
        .sort_by { |_, count| -count }
        .each { |term, count| f.puts "#{term}\t#{count}" }
end
```

## Development

After checking out the repo:

```bash
bundle install
bundle exec rake compile
bundle exec rake spec
```

To build the gem:

```bash
bundle exec rake build
```

## Platform Support

Pre-built gems available for:
- macOS (x86_64, arm64)
- Linux (glibc, musl)
- Ruby 3.1, 3.2, 3.3

## Contributing

Bug reports and pull requests are welcome at https://github.com/scientist-labs/spellkit

## License

MIT License - see [LICENSE](LICENSE) file for details.
