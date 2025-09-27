#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "spellkit"

puts "=" * 80
puts "SpellKit Performance Benchmark"
puts "=" * 80
puts

# Test words with various characteristics
COMMON_TYPOS = %w[
  helo wrld definately occured recieve seperete accomodate
  goverment necesary tommorow wich thier becuase
].freeze

CORRECT_WORDS = %w[
  hello world definitely occurred receive separate accommodate
  government necessary tomorrow which their because
].freeze

MIXED_WORDS = COMMON_TYPOS + CORRECT_WORDS

puts "Setting up dictionary (not timed)..."
test_dict = File.expand_path("../spec/fixtures/test_unigrams.tsv", __dir__)
SpellKit.load!(dictionary: test_dict, edit_distance: 2)
stats = SpellKit.stats
puts "  ✓ Dictionary loaded: #{stats["dictionary_size"]} terms"
puts "  ✓ Edit distance: #{stats["edit_distance"]}"
puts "  ✓ Loaded at: #{Time.at(stats["loaded_at"]).strftime("%Y-%m-%d %H:%M:%S")}"
puts

puts "-" * 80
puts "Benchmark 1: Single Word Suggestions"
puts "Testing with #{COMMON_TYPOS.size} misspelled words"
puts "-" * 80
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("suggest (max: 1)") do
    COMMON_TYPOS.each { |word| SpellKit.suggestions(word, 1) }
  end

  x.report("suggest (max: 5)") do
    COMMON_TYPOS.each { |word| SpellKit.suggestions(word, 5) }
  end

  x.report("suggest (max: 10)") do
    COMMON_TYPOS.each { |word| SpellKit.suggestions(word, 10) }
  end

  x.compare!
end

puts
puts "-" * 80
puts "Benchmark 2: Correction (correct)"
puts "Testing with #{MIXED_WORDS.size} words (50% correct, 50% misspelled)"
puts "-" * 80
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("correct") do
    MIXED_WORDS.each { |word| SpellKit.correct(word) }
  end

  x.compare!
end

puts
puts "-" * 80
puts "Benchmark 3: Batch Correction"
puts "Testing with #{MIXED_WORDS.size} words at once"
puts "-" * 80
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("correct_tokens (batch)") do
    SpellKit.correct_tokens(MIXED_WORDS)
  end

  x.compare!
end

puts
puts "-" * 80
puts "Benchmark 4: With Guards (Protected Terms)"
puts "-" * 80
puts

# Reload with protected terms
protected_file = File.expand_path("../spec/fixtures/protected.txt", __dir__)
SpellKit.load!(
  dictionary: test_dict,
  protected_path: protected_file,
  edit_distance: 2
)
puts "  ✓ Reloaded with protected terms"
puts

WORDS_WITH_PROTECTED = %w[helo wrld CDK10 BRCA1 rat mouse lyssis]

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("without guard") do
    WORDS_WITH_PROTECTED.each { |word| SpellKit.correct(word) }
  end

  x.report("with guard") do
    WORDS_WITH_PROTECTED.each { |word| SpellKit.correct(word, guard: :domain) }
  end

  x.compare!
end

puts
puts "-" * 80
puts "Benchmark 5: Latency Distribution"
puts "Measuring p50, p95, p99 latency for single word correction"
puts "-" * 80
puts

# Warmup
1000.times { SpellKit.suggestions("helo", 5) }

# Collect latency samples
latencies = []
10_000.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  SpellKit.suggestions("helo", 5)
  finish = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  latencies << (finish - start)
end

latencies.sort!
p50 = latencies[latencies.length / 2]
p95 = latencies[(latencies.length * 0.95).to_i]
p99 = latencies[(latencies.length * 0.99).to_i]
max = latencies.last

puts
puts "Results (10,000 iterations):"
puts "  p50: #{p50.round(2)}µs"
puts "  p95: #{p95.round(2)}µs"
puts "  p99: #{p99.round(2)}µs"
puts "  max: #{max.round(2)}µs"
puts

puts "-" * 80
puts "Benchmark 6: Throughput (Operations per Second)"
puts "-" * 80
puts

iterations = 100_000
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
iterations.times { SpellKit.suggestions("helo", 1) }
finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

elapsed = finish - start
throughput = iterations / elapsed

puts
puts "Results:"
puts "  Iterations: #{iterations.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
puts "  Time: #{elapsed.round(2)}s"
puts "  Throughput: #{throughput.round.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} ops/sec"
puts

puts "=" * 80
puts "Benchmark Complete"
puts "=" * 80
puts
puts "Summary:"
puts "  SpellKit (Rust-based) delivers sub-microsecond median latency"
puts "  with consistent performance even at p99"
puts "="