# SpellKit

Fast, safe typo correction for search-term extraction, wrapping the SymSpell algorithm in Rust via Magnus.

SpellKit provides:
- **Fast correction** using SymSpell with configurable edit distance (1 or 2)
- **Domain protection** - never alter protected terms like gene symbols (CDK10, IL-6), CAS numbers, SKUs, or species names
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

```ruby
require "spellkit"

# Load your dictionary
SpellKit.load!(
  unigrams_path: "models/unigrams.tsv",
  symbols_path: "models/symbols.txt",      # optional
  species_path: "models/species.txt",      # optional
  edit_distance: 1                         # 1 (default) or 2
)

# Get suggestions
SpellKit.suggest("lyssis", max: 5)
# => [{"term"=>"lysis", "distance"=>1, "freq"=>2000}, ...]

# Correct a typo
SpellKit.correct_if_unknown("helo")
# => "hello"

# Protect domain terms
SpellKit.correct_if_unknown("CDK10", guard: :domain)
# => "CDK10"  # protected, never changed

# Batch correction
tokens = %w[rat lyssis buffers for CDK10]
SpellKit.correct_tokens(tokens, guard: :domain)
# => ["rat", "lysis", "buffer", "for", "CDK10"]
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

One term per line:

**symbols.txt**
```
CDK10
BRCA1
IL6
IL-6
```

**species.txt**
```
rat
mouse
human
```

**cas.txt**
```
7732-18-5
50-00-0
```

**skus.txt**
```
ABC-12345
XYZ-99999
```

## Configuration

```ruby
SpellKit.load!(
  unigrams_path: "models/unigrams.tsv",     # required
  symbols_path: "models/symbols.txt",        # optional
  cas_path: "models/cas.txt",                # optional
  skus_path: "models/skus.txt",              # optional
  species_path: "models/species.txt",        # optional
  manifest_path: "models/symspell.json",     # optional
  edit_distance: 1,                          # 1 (default) or 2
  frequency_threshold: 10.0                  # default: 10.0
)
```

## API Reference

### `SpellKit.load!(**options)`

Load or reload dictionaries. Thread-safe atomic swap.

**Options:**
- `unigrams_path:` (required) - Path to TSV file with term<TAB>frequency
- `symbols_path:` (optional) - Path to protected gene/protein symbols
- `cas_path:` (optional) - Path to protected CAS numbers
- `skus_path:` (optional) - Path to protected SKUs
- `species_path:` (optional) - Path to protected species names
- `manifest_path:` (optional) - Path to JSON manifest with version info
- `edit_distance:` (default: 1) - Maximum edit distance (1 or 2)
- `frequency_threshold:` (default: 10.0) - Minimum frequency ratio for corrections

### `SpellKit.suggest(word, max:)`

Get ranked suggestions for a word.

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

## Guards & Domain Protection

The `guard: :domain` option enables protection for domain-specific terms:

### Regex Patterns
- **Symbols**: Matches patterns like `CDK10`, `BRCA1`, `IL-6`
- **CAS Numbers**: Matches `\d{2,7}-\d{2}-\d` format

### Set Membership
Terms in protected lists are never corrected, even if similar dictionary words exist.

### Variants
SpellKit automatically handles common variants:
- `IL-6` and `IL6` (with/without hyphen)
- Case-insensitive matching for most terms
- Preserves original casing in output

## Rails Integration

```ruby
# config/initializers/spellkit.rb
SpellKit.load!(
  unigrams_path: Rails.root.join("models/unigrams.tsv"),
  symbols_path: Rails.root.join("models/symbols.txt"),
  species_path: Rails.root.join("models/species.txt"),
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