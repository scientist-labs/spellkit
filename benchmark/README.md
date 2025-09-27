# SpellKit Benchmarks

This directory contains benchmark scripts for evaluating SpellKit's performance.

## Available Benchmarks

### 1. Performance Benchmark (`performance.rb`)

Comprehensive performance analysis of SpellKit including:
- Single word suggestions with varying result limits
- Correction performance on mixed datasets
- Batch correction throughput
- Guard/protection overhead
- Latency distribution (p50, p95, p99)
- Raw throughput (ops/sec)

**Run it:**
```bash
bundle exec ruby benchmark/performance.rb
```

### 2. Aspell Comparison (`comparison_aspell.rb`)

Direct comparison between SpellKit and Aspell (if installed).

**Requirements:**
- Aspell must be installed on your system
- macOS: `brew install aspell`
- Ubuntu: `sudo apt-get install aspell libaspell-dev`

**Run it:**
```bash
bundle exec ruby benchmark/comparison_aspell.rb
```

### 3. Hunspell Comparison (`comparison_hunspell.rb`)

Direct comparison between SpellKit and Hunspell.

**Requirements:**
- Hunspell must be installed with English dictionaries
- macOS: `brew install hunspell && brew install hunspell-en`
- Ubuntu: `sudo apt-get install hunspell libhunspell-dev hunspell-en-us`

**Run it:**
```bash
bundle exec ruby benchmark/comparison_hunspell.rb
```

## Recent Results

### SpellKit Performance (M1 MacBook Pro, Ruby 3.3.0)

**Single Word Suggestions (13 words):**
- suggest (max: 1): 16,985 i/s (58.88 μs/i)
- suggest (max: 5): 16,454 i/s (60.78 μs/i)
- suggest (max: 10): 16,370 i/s (61.09 μs/i)

**Correction (26 mixed words):**
- correct_if_unknown: 7,348 i/s (136.09 μs/i)

**Batch Correction (26 words):**
- correct_tokens: 8,235 i/s (121.43 μs/i)

**Guard Performance (7 words):**
- without guard: 59,217 i/s (16.89 μs/i)
- with guard: 105,685 i/s (9.46 μs/i) - 1.78x **faster**!
  *(Guards short-circuit expensive lookups)*

**Latency Distribution (10,000 iterations):**
- p50: 3μs
- p95: 4μs
- p99: 23μs
- max: 216μs

**Throughput:**
- **352,108 ops/sec** on single word suggestions

## Key Takeaways

1. **Consistent Performance**: p95 and p99 latencies remain low (< 25μs)
2. **Guards are Fast**: Protected term checks actually improve performance by avoiding expensive dictionary lookups
3. **High Throughput**: Over 350k operations per second for spell checking
4. **Scales Well**: Minimal performance difference between requesting 1 vs 10 suggestions

## Running Comparisons with Other Libraries

The comparison benchmarks require external spell checking libraries to be installed:

- **Aspell**: `brew install aspell` (macOS) or `sudo apt-get install aspell libaspell-dev` (Ubuntu)
- **Hunspell**: `brew install hunspell hunspell-en` (macOS) or `sudo apt-get install hunspell libhunspell-dev hunspell-en-us` (Ubuntu)

If these libraries are not installed, the comparison scripts will provide installation instructions and exit gracefully.

## Dictionary Note

The test dictionary used in these benchmarks is small (20 terms) for reproducibility. Real-world performance with larger dictionaries (80k+ terms) will be different but should maintain similar latency characteristics due to the SymSpell algorithm's O(1) lookup complexity.

## Why Compare Different Spell Checkers?

Different spell checking libraries use different algorithms optimized for different use cases:

- **SpellKit (SymSpell)**: O(1) lookup complexity, optimized for speed with large dictionaries and fuzzy matching with suggestions
- **Aspell**: Statistical scoring with phonetic similarity, good for natural language text
- **Hunspell**: Affix compression and complex morphological rules, excellent for languages with rich morphology

All three provide **fuzzy matching and suggestions** for misspelled words, making them comparable approaches to the same problem.

Choose the tool that best fits your use case!
