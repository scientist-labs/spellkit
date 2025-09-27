#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "spellkit"

# Try to load ffi-hunspell
begin
  require "ffi/hunspell"
  HUNSPELL_AVAILABLE = true
rescue LoadError => e
  HUNSPELL_AVAILABLE = false
  puts "⚠️  ffi-hunspell gem error: #{e.message}"
end

puts "=" * 80
puts "SpellKit vs Hunspell Benchmark"
puts "=" * 80
puts

unless HUNSPELL_AVAILABLE
  puts "❌ Hunspell is not installed or ffi-hunspell gem failed to load"
  puts
  puts "To install Hunspell:"
  puts "  macOS:   brew install hunspell"
  puts "  Ubuntu:  sudo apt-get install hunspell libhunspell-dev"
  puts "  Fedora:  sudo dnf install hunspell hunspell-devel"
  puts
  puts "You may also need to install dictionary files:"
  puts "  macOS:   brew install hunspell-en"
  puts "  Ubuntu:  sudo apt-get install hunspell-en-us"
  puts
  exit 1
end

# Test words with common misspellings
TEST_WORDS = %w[
  helo wrld definately occured recieve seperete accomodate
  goverment necesary tommorow wich thier becuase
].freeze

CORRECT_WORDS = %w[
  hello world definitely occurred receive separate accommodate
  government necessary tomorrow which their because
].freeze

MIXED_WORDS = TEST_WORDS + CORRECT_WORDS

puts "Setting up spell checkers (not timed)..."
puts

# 1. Setup SpellKit (Rust implementation)
puts "Loading SpellKit dictionary..."
spellkit_dict = File.expand_path("../spec/fixtures/test_unigrams.tsv", __dir__)
SpellKit.load!(dictionary: spellkit_dict, edit_distance: 2)
puts "  ✓ SpellKit loaded: #{SpellKit.stats["dictionary_size"]} terms"

# 2. Setup Hunspell
puts "Initializing Hunspell..."
begin
  # Try to open US English dictionary
  hunspell = FFI::Hunspell.dict("en_US")
  puts "  ✓ Hunspell initialized with en_US dictionary"
rescue ArgumentError
  puts "  ✗ en_US dictionary not found, trying en_GB..."
  begin
    hunspell = FFI::Hunspell.dict("en_GB")
    puts "  ✓ Hunspell initialized with en_GB dictionary"
  rescue ArgumentError
    puts "  ✗ No English dictionaries found"
    puts
    puts "Please install dictionary files:"
    puts "  macOS:   brew install hunspell-en"
    puts "  Ubuntu:  sudo apt-get install hunspell-en-us"
    exit 1
  end
end

puts
puts "-" * 80
puts "Benchmark 1: Spell checking (is word correct?)"
puts "Testing with #{MIXED_WORDS.size} words (50% correct, 50% misspelled)"
puts "-" * 80
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("SpellKit") do
    MIXED_WORDS.each do |word|
      result = SpellKit.suggest(word, 1)
      result.first && result.first["distance"] == 0
    end
  end

  x.report("Hunspell") do
    MIXED_WORDS.each do |word|
      hunspell.check?(word)
    end
  end

  x.compare!
end

puts
puts "-" * 80
puts "Benchmark 2: Getting suggestions for misspelled words"
puts "Testing with #{TEST_WORDS.size} misspelled words"
puts "-" * 80
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("SpellKit (5 suggestions)") do
    TEST_WORDS.each do |word|
      SpellKit.suggest(word, 5)
    end
  end

  x.report("Hunspell (all suggestions)") do
    TEST_WORDS.each do |word|
      hunspell.suggest(word)
    end
  end

  x.compare!
end

puts
puts "-" * 80
puts "Benchmark 3: Single word correction"
puts "-" * 80
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("SpellKit") do
    TEST_WORDS.each do |word|
      SpellKit.correct_if_unknown(word)
    end
  end

  x.report("Hunspell") do
    TEST_WORDS.each do |word|
      suggestions = hunspell.suggest(word)
      suggestions.empty? ? word : suggestions.first
    end
  end

  x.compare!
end

puts
puts "-" * 80
puts "Benchmark 4: Batch correction"
puts "Processing #{MIXED_WORDS.size} words in batch"
puts "-" * 80
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("SpellKit (batch API)") do
    SpellKit.correct_tokens(MIXED_WORDS)
  end

  x.report("Hunspell (loop)") do
    MIXED_WORDS.map do |word|
      if hunspell.check?(word)
        word
      else
        suggestions = hunspell.suggest(word)
        suggestions.empty? ? word : suggestions.first
      end
    end
  end

  x.compare!
end

puts
puts "-" * 80
puts "Benchmark 5: Latency Distribution"
puts "-" * 80
puts

# Warmup
1000.times { SpellKit.suggest("helo", 5) }
1000.times { hunspell.suggest("helo") }

# Collect latency samples for SpellKit
latencies_spellkit = []
10_000.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  SpellKit.suggest("helo", 5)
  finish = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  latencies_spellkit << (finish - start)
end

# Collect latency samples for Hunspell
latencies_hunspell = []
10_000.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  hunspell.suggest("helo")
  finish = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  latencies_hunspell << (finish - start)
end

def percentiles(data)
  sorted = data.sort
  {
    p50: sorted[sorted.length / 2],
    p95: sorted[(sorted.length * 0.95).to_i],
    p99: sorted[(sorted.length * 0.99).to_i],
    max: sorted.last
  }
end

spellkit_stats = percentiles(latencies_spellkit)
hunspell_stats = percentiles(latencies_hunspell)

puts
puts "SpellKit (10,000 iterations):"
puts "  p50: #{spellkit_stats[:p50].round(2)}µs"
puts "  p95: #{spellkit_stats[:p95].round(2)}µs"
puts "  p99: #{spellkit_stats[:p99].round(2)}µs"
puts "  max: #{spellkit_stats[:max].round(2)}µs"
puts
puts "Hunspell (10,000 iterations):"
puts "  p50: #{hunspell_stats[:p50].round(2)}µs"
puts "  p95: #{hunspell_stats[:p95].round(2)}µs"
puts "  p99: #{hunspell_stats[:p99].round(2)}µs"
puts "  max: #{hunspell_stats[:max].round(2)}µs"
puts
puts "SpellKit Speed Advantage:"
puts "  p50: #{(hunspell_stats[:p50] / spellkit_stats[:p50]).round(2)}x faster"
puts "  p95: #{(hunspell_stats[:p95] / spellkit_stats[:p95]).round(2)}x faster"

puts
puts "=" * 80
puts "Benchmark Complete"
puts "=" * 80
puts
puts "Note: SpellKit uses SymSpell algorithm (O(1) lookup complexity)"
puts "      Hunspell uses affix compression and complex morphological rules"
puts "      Different algorithms optimized for different use cases"