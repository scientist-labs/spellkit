# SpellKit

Fast, safe typo correction for search-term extraction, wrapping the SymSpell algorithm in Rust via Magnus.

SpellKit provides:
- **Fast correction** using SymSpell with configurable edit distance (1 or 2)
- **Term protection** - never alter protected terms using exact matches or regex patterns
- **Hot reload** - update dictionaries without restarting your application
- **Sub-millisecond latency** - p95 < 2µs on small dictionaries
- **Thread-safe** - built with Rust's Arc<RwLock> for safe concurrent access

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

# Get suggestions for a misspelled word
suggestions = SpellKit.suggest("helo", 5)
puts suggestions.inspect
# => [{"term"=>"hello", "distance"=>1, "freq"=>...}]

# Correct a typo
corrected = SpellKit.correct_if_unknown("helo")
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

# Get suggestions
SpellKit.suggest("lyssis", 5)
# => [{"term"=>"lysis", "distance"=>1, "freq"=>2000}, ...]

# Correct a typo
SpellKit.correct_if_unknown("helo")
# => "hello"

# Batch correction
tokens = %w[helo wrld ruby]
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
SpellKit.correct_if_unknown("CDK10", guard: :domain)
# => "CDK10"  # protected, never changed

# Batch correction with guards
tokens = %w[helo wrld ABC-123 for CDK10]
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
medical_checker.suggest("lyssis", 5)
legal_checker.suggest("contractt", 5)

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
  config.manifest_path = "models/symspell.json"
  config.edit_distance = 1
  config.frequency_threshold = 10.0
end

# This becomes the default instance
SpellKit.suggest("word", 5)  # Uses configured dictionary
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
  manifest_path: "models/symspell.json",             # optional
  edit_distance: 1,                                  # 1 (default) or 2
  frequency_threshold: 10.0                          # default: 10.0
)
```

## API Reference

### `SpellKit.load!(**options)`

Load or reload dictionaries. Thread-safe atomic swap. Accepts URLs (auto-downloads and caches) or local file paths.

**Options:**
- `dictionary:` (required) - URL or path to TSV file with term<TAB>frequency
- `protected_path:` (optional) - Path to file with protected terms (one per line)
- `protected_patterns:` (optional) - Array of Regexp or String patterns to protect
- `manifest_path:` (optional) - Path to JSON manifest with version info
- `edit_distance:` (default: 1) - Maximum edit distance (1 or 2)
- `frequency_threshold:` (default: 10.0) - Minimum frequency ratio for corrections

**Examples:**
```ruby
# From URL (recommended for getting started)
SpellKit.load!(dictionary: SpellKit::DEFAULT_DICTIONARY_URL)

# From custom URL
SpellKit.load!(dictionary: "https://example.com/dict.tsv")

# From local file
SpellKit.load!(dictionary: "/path/to/dictionary.tsv")
```

### `SpellKit.suggest(word, max = 5)`

Get ranked suggestions for a word.

**Parameters:**
- `word` (required) - The word to get suggestions for
- `max` (optional, default: 5) - Maximum number of suggestions to return

**Returns:** Array of hashes with `"term"`, `"distance"`, and `"freq"` keys

### `SpellKit.correct_if_unknown(word, guard:)`

Return corrected word or original if no better match found.

**Options:**
- `guard:` - Set to `:domain` to enable protection checks

### `SpellKit.correct_tokens(tokens, guard:)`

Batch correction of an array of tokens.

**Returns:** Array of corrected strings

### `SpellKit.stats`

Get current state statistics.

**Returns:** Hash with:
- `"loaded"` - Boolean
- `"dictionary_size"` - Number of terms
- `"edit_distance"` - Configured edit distance
- `"loaded_at"` - Unix timestamp
- `"version"` - Manifest version (if provided)

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

Benchmarked on M1 MacBook Pro with 20-term test dictionary:

- **Load time**: < 100ms
- **Suggestion latency**: p50 < 2µs, p95 < 2µs
- **Guard checks**: p95 < 1µs
- **Memory**: ~150MB for 1M term dictionary (estimated)

Target for production (1-5M terms):
- Load: < 500ms
- p50: < 30µs, p95: < 100µs
- Memory: 50-150MB

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
