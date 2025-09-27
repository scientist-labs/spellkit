RSpec.describe "Refactored Correction Logic" do
  let(:test_unigrams) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }
  let(:protected_file) { File.expand_path("fixtures/protected.txt", __dir__) }

  describe "single-word and batch corrections behave identically" do
    it "produces identical results without guards" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 2)

      test_words = %w[helo wrld tst heo st incubatio buffers]

      # Single-word corrections
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections
      batch_results = SpellKit.correct_tokens(test_words)

      # Should be identical
      expect(batch_results).to eq(single_results)
    end

    it "produces identical results with guards enabled" do
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_path: protected_file,
        edit_distance: 2
      )

      test_words = %w[helo CDK10 BRCA1 wrld rat lyssis]

      # Single-word corrections with guard
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections with guard
      batch_results = SpellKit.correct_tokens(test_words)

      # Should be identical
      expect(batch_results).to eq(single_results)
    end

    it "produces identical results with frequency threshold" do
      SpellKit.load!(
        dictionary: test_unigrams,
        edit_distance: 2,
        frequency_threshold: 1000.0
      )

      test_words = %w[helo incubatio tst heo]

      # Single-word corrections
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections
      batch_results = SpellKit.correct_tokens(test_words)

      # Should be identical
      expect(batch_results).to eq(single_results)
    end

    it "produces identical results with edit_distance: 1" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 1)

      test_words = %w[helo heo st tst]

      # Single-word corrections
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections
      batch_results = SpellKit.correct_tokens(test_words)

      # Should be identical
      expect(batch_results).to eq(single_results)
    end

    it "produces identical results with all features combined" do
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_path: protected_file,
        protected_patterns: [/^IL-?\d+$/i],
        edit_distance: 2,
        frequency_threshold: 100.0
      )

      test_words = %w[helo CDK10 IL6 wrld heo incubatio rat lyssis]

      # Single-word corrections with guard
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections with guard
      batch_results = SpellKit.correct_tokens(test_words)

      # Should be identical
      expect(batch_results).to eq(single_results)
    end

    it "handles exact matches identically" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 2)

      test_words = %w[hello world test testing]

      # Single-word corrections (all exact matches)
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections (all exact matches)
      batch_results = SpellKit.correct_tokens(test_words)

      # All should remain unchanged
      expect(batch_results).to eq(test_words)
      expect(single_results).to eq(test_words)
    end

    it "handles unknown words identically" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 1)

      test_words = %w[xyzabc qwerty zzzzzz]

      # Single-word corrections (no matches)
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections (no matches)
      batch_results = SpellKit.correct_tokens(test_words)

      # All should remain unchanged (no corrections found)
      expect(batch_results).to eq(test_words)
      expect(single_results).to eq(test_words)
    end

    it "handles empty token array" do
      SpellKit.load!(dictionary: test_unigrams)

      batch_results = SpellKit.correct_tokens([])

      expect(batch_results).to eq([])
    end

    it "produces identical results with protected_patterns (regex)" do
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [/^CDK\d+$/, /^IL-?\d+$/i],
        edit_distance: 2
      )

      test_words = %w[helo CDK10 IL6 il-6 wrld]

      # Single-word corrections with guard
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections with guard
      batch_results = SpellKit.correct_tokens(test_words)

      # Should be identical
      expect(batch_results).to eq(single_results)

      # Verify protected terms weren't corrected
      expect(batch_results[1]).to eq("CDK10")
      expect(batch_results[2]).to eq("IL6")
      expect(batch_results[3]).to eq("il-6")  # Case-insensitive pattern
    end

    it "handles mixed scenarios (corrected, protected, unchanged, unknown)" do
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_path: protected_file,
        edit_distance: 1
      )

      # Mix of different scenarios
      test_words = %w[
        helo
        CDK10
        hello
        xyzabc
        wrld
        BRCA1
        test
        qwerty
      ]

      # Single-word corrections
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections
      batch_results = SpellKit.correct_tokens(test_words)

      # Should be identical
      expect(batch_results).to eq(single_results)

      # Verify expected behavior
      expect(batch_results[0]).to eq("hello")   # Corrected
      expect(batch_results[1]).to eq("CDK10")   # Protected
      expect(batch_results[2]).to eq("hello")   # Exact match
      expect(batch_results[3]).to eq("xyzabc")  # Unknown (no correction)
      expect(batch_results[4]).to eq("world")   # Corrected
      expect(batch_results[5]).to eq("BRCA1")   # Protected
      expect(batch_results[6]).to eq("test")    # Exact match
      expect(batch_results[7]).to eq("qwerty")  # Unknown (no correction)
    end

    it "handles case variations identically" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 1)

      test_words = %w[HELLO HeLLo hello WRLD world]

      # Single-word corrections
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections
      batch_results = SpellKit.correct_tokens(test_words)

      # Should be identical (normalization applies to all)
      expect(batch_results).to eq(single_results)

      # All should return canonical form from dictionary (which is lowercase "hello")
      expect(batch_results[0]).to eq("hello")  # Returns canonical form
      expect(batch_results[1]).to eq("hello")  # Returns canonical form
      expect(batch_results[2]).to eq("hello")  # Returns canonical form
      expect(batch_results[3]).to eq("world")  # Returns canonical form
      expect(batch_results[4]).to eq("world")  # Returns canonical form
    end

    it "handles single-word batch" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 2)

      word = "helo"

      # Single-word correction
      single_result = SpellKit.correct(word)

      # Batch with one word
      batch_results = SpellKit.correct_tokens([word])

      # Should be identical
      expect(batch_results).to eq([single_result])
      expect(batch_results.first).to eq("hello")
    end

    it "preserves token order in batch" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 2)

      # Intentionally unordered words
      test_words = %w[zzz helo aaa wrld mmm tst]

      # Single-word corrections (maintaining order)
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections (should maintain order)
      batch_results = SpellKit.correct_tokens(test_words)

      # Should be identical and in same order
      expect(batch_results).to eq(single_results)

      # Verify order
      expect(batch_results[0]).to eq("zzz")    # Unknown
      expect(batch_results[1]).to eq("hello")  # Corrected
      expect(batch_results[2]).to eq("aaa")    # Unknown
      expect(batch_results[3]).to eq("world")  # Corrected
      expect(batch_results[4]).to eq("mmm")    # Unknown
      expect(batch_results[5]).to eq("test")   # Corrected
    end

    it "handles duplicate words in batch identically" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 1)

      # Same word multiple times
      test_words = %w[helo helo wrld helo wrld]

      # Single-word corrections
      single_results = test_words.map { |word| SpellKit.correct(word) }

      # Batch corrections
      batch_results = SpellKit.correct_tokens(test_words)

      # Should be identical
      expect(batch_results).to eq(single_results)

      # All "helo" should become "hello"
      expect(batch_results).to eq(%w[hello hello world hello world])
    end
  end

  describe "maintains single-lock optimization in batch mode" do
    it "processes large batches efficiently" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 2)

      # Create a large batch of tokens
      large_batch = (%w[helo wrld tst] * 100).shuffle

      # Time batch correction (should be fast with single lock)
      start_time = Time.now
      batch_results = SpellKit.correct_tokens(large_batch)
      batch_time = Time.now - start_time

      # Time individual corrections (will acquire lock 300 times)
      start_time = Time.now
      single_results = large_batch.map { |word| SpellKit.correct(word) }
      single_time = Time.now - start_time

      # Results should be identical
      expect(batch_results).to eq(single_results)

      # Batch should be significantly faster (not a strict assertion, just informational)
      puts "\nBatch time: #{(batch_time * 1000).round(2)}ms"
      puts "Single time: #{(single_time * 1000).round(2)}ms"
      puts "Speedup: #{(single_time / batch_time).round(2)}x"
    end
  end
end