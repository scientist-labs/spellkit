#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "spellkit"

# Try to load ffi-aspell
begin
  require "ffi/aspell"
  ASPELL_AVAILABLE = true
rescue LoadError
  ASPELL_AVAILABLE = false
  puts "⚠️  ffi-aspell not available"
end

puts "=" * 80
puts "SpellKit vs Aspell Benchmark"
puts "=" * 80
puts

unless ASPELL_AVAILABLE
  puts "❌ Aspell is not installed or ffi-aspell gem is not available"
  puts
  puts "To install Aspell:"
  puts "  macOS:   brew install aspell"
  puts "  Ubuntu:  sudo apt-get install aspell libaspell-dev"
  puts "  Fedora:  sudo dnf install aspell aspell-devel"
  puts
  exit 1
end

# Test words with common misspellings
TEST_WORDS = %w[
  helo wrld definately occured recieve seperete accomodate
  goverment necesary tommorow wich thier becuase
].freeze

puts "Setting up spell checkers (not timed)..."
puts

# 1. Setup SpellKit (Rust implementation)
puts "Loading SpellKit dictionary..."
spellkit_dict = File.expand_path("../spec/fixtures/test_unigrams.tsv", __dir__)
SpellKit.load!(dictionary: spellkit_dict, edit_distance: 2)
puts "  ✓ SpellKit loaded: #{SpellKit.stats["dictionary_size"]} terms"

# 2. Setup Aspell
puts "Initializing Aspell..."
aspell = FFI::Aspell::Speller.new("en_US")
puts "  ✓ Aspell initialized"

puts
puts "-" * 80
puts "Benchmark: Single word correction"
puts "Testing with #{TEST_WORDS.size} misspelled words"
puts "-" * 80
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("SpellKit (Rust)") do
    TEST_WORDS.each do |word|
      SpellKit.suggest(word, 5)
    end
  end

  x.report("Aspell (C)") do
    TEST_WORDS.each do |word|
      aspell.suggestions(word)
    end
  end

  x.compare!
end

puts
puts "-" * 80
puts "Benchmark: Spell checking (is word correct?)"
puts "-" * 80
puts

MIXED_WORDS = TEST_WORDS + %w[hello world definitely occurred receive separate]

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("SpellKit") do
    MIXED_WORDS.each do |word|
      SpellKit.correct?(word)
    end
  end

  x.report("Aspell") do
    MIXED_WORDS.each do |word|
      aspell.correct?(word)
    end
  end

  x.compare!
end

puts
puts "-" * 80
puts "Benchmark: Latency Distribution (SpellKit)"
puts "-" * 80
puts

# Warmup
1000.times { SpellKit.suggest("helo", 5) }

# Collect latency samples for SpellKit
latencies_spellkit = []
10_000.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  SpellKit.suggest("helo", 5)
  finish = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  latencies_spellkit << (finish - start)
end

# Collect latency samples for Aspell
latencies_aspell = []
10_000.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  aspell.suggestions("helo")
  finish = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  latencies_aspell << (finish - start)
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
aspell_stats = percentiles(latencies_aspell)

puts
puts "SpellKit (10,000 iterations):"
puts "  p50: #{spellkit_stats[:p50].round(2)}µs"
puts "  p95: #{spellkit_stats[:p95].round(2)}µs"
puts "  p99: #{spellkit_stats[:p99].round(2)}µs"
puts "  max: #{spellkit_stats[:max].round(2)}µs"
puts
puts "Aspell (10,000 iterations):"
puts "  p50: #{aspell_stats[:p50].round(2)}µs"
puts "  p95: #{aspell_stats[:p95].round(2)}µs"
puts "  p99: #{aspell_stats[:p99].round(2)}µs"
puts "  max: #{aspell_stats[:max].round(2)}µs"
puts
puts "SpeedUp:"
puts "  p50: #{(aspell_stats[:p50] / spellkit_stats[:p50]).round(2)}x faster"
puts "  p95: #{(aspell_stats[:p95] / spellkit_stats[:p95]).round(2)}x faster"

puts
puts "=" * 80
puts "Benchmark Complete"
puts "=" * 80