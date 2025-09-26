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

Copy and paste this to try SpellKit immediately after installation:

```ruby
require "spellkit"
require "tempfile"

# Create a simple dictionary
dict = Tempfile.new(["unigrams", ".tsv"])
dict.write("hello\t10000\nworld\t5000\nruby\t3000\ntest\t2000\n")
dict.close

# Load the dictionary
SpellKit.load!(unigrams_path: dict.path, edit_distance: 1)

# Get suggestions for a misspelled word
suggestions = SpellKit.suggest("helo", 5)
puts suggestions.inspect
# => [{"term"=>"hello", "distance"=>1, "freq"=>10000}]

# Correct a typo
corrected = SpellKit.correct_if_unknown("helo")
puts corrected
# => "hello"

# Batch correction
tokens = %w[helo wrld ruby tset]
corrected_tokens = SpellKit.correct_tokens(tokens)
puts corrected_tokens.inspect
# => ["hello", "world", "ruby", "test"]

# Check stats
puts SpellKit.stats.inspect
# => {"loaded"=>true, "dictionary_size"=>4, "edit_distance"=>1, "loaded_at"=>...}

dict.unlink
```

## Usage

### Basic Correction

```ruby
require "spellkit"

# Load your dictionary
SpellKit.load!(
  unigrams_path: "models/unigrams.tsv",
  edit_distance: 1
)

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
  unigrams_path: "models/unigrams.tsv",
  protected_path: "models/protected.txt"   # file with terms to protect
)

# Protect terms matching regex patterns
SpellKit.load!(
  unigrams_path: "models/unigrams.tsv",
  protected_patterns: [
    /^[A-Z]{3,4}\d+$/,        # gene symbols like CDK10, BRCA1
    /^\d{2,7}-\d{2}-\d$/,     # CAS numbers like 7732-18-5
    /^[A-Z]{2,3}-\d+$/        # SKU patterns like ABC-123
  ]
)

# Or combine both
SpellKit.load!(
  unigrams_path: "models/unigrams.tsv",
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

## Dictionary Format

### Unigrams (required)

Tab-separated file with term and frequency:

```
hello	10000
world	8000
lysis	2000
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

## Configuration

```ruby
SpellKit.load!(
  unigrams_path: "models/unigrams.tsv",              # required
  protected_path: "models/protected.txt",            # optional
  protected_patterns: [/^[A-Z]{3,4}\d+$/],           # optional
  manifest_path: "models/symspell.json",             # optional
  edit_distance: 1,                                  # 1 (default) or 2
  frequency_threshold: 10.0                          # default: 10.0
)
```

## API Reference

### `SpellKit.load!(**options)`

Load or reload dictionaries. Thread-safe atomic swap.

**Options:**
- `unigrams_path:` (required) - Path to TSV file with term<TAB>frequency
- `protected_path:` (optional) - Path to file with protected terms (one per line)
- `protected_patterns:` (optional) - Array of Regexp or String patterns to protect
- `manifest_path:` (optional) - Path to JSON manifest with version info
- `edit_distance:` (default: 1) - Maximum edit distance (1 or 2)
- `frequency_threshold:` (default: 10.0) - Minimum frequency ratio for corrections

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
SpellKit.load!(
  unigrams_path: Rails.root.join("models/unigrams.tsv"),
  protected_path: Rails.root.join("models/protected.txt"),
  protected_patterns: [
    /^[A-Z]{3,4}\d+$/,     # Product codes
    /^\d{2,7}-\d{2}-\d$/   # Reference numbers
  ],
  edit_distance: 1
)

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

Create your unigrams dictionary from your corpus:

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
File.open("unigrams.tsv", "w") do |f|
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