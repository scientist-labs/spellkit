require "tempfile"

RSpec.describe "Dictionary Validation" do
  let(:malformed_dict) { File.expand_path("fixtures/malformed_dictionary.tsv", __dir__) }

  describe "error tracking" do
    it "tracks malformed lines (wrong number of columns)" do
      SpellKit.load!(dictionary: malformed_dict)

      stats = SpellKit.stats

      # Should load valid entries
      expect(stats["dictionary_size"]).to be > 0

      # Should track malformed lines:
      # - "test" (1 column)
      # - "missing_frequency" (1 column)
      # - "extra	column	here	100" (4 columns)
      expect(stats["skipped_malformed"]).to eq(3)
    end

    it "supports multi-word terms by normalizing them" do
      SpellKit.load!(dictionary: malformed_dict)

      stats = SpellKit.stats

      # Multi-word terms are now supported via normalization:
      # - "New York	5000" normalizes to "newyork" but preserves canonical form
      # - "cell culture	3000" normalizes to "cellculture" but preserves canonical form
      expect(stats["skipped_multiword"]).to eq(0)

      # Verify they can be looked up and return canonical forms
      expect(SpellKit.correct("newyork")).to eq("New York")
      expect(SpellKit.correct("cellculture")).to eq("cell culture")
    end

    it "tracks invalid frequency values" do
      SpellKit.load!(dictionary: malformed_dict)

      stats = SpellKit.stats

      # Should track invalid frequencies:
      # - "bad_freq	not_a_number" (frequency not parseable)
      expect(stats["skipped_invalid_freq"]).to eq(1)
    end

    it "loads valid entries correctly" do
      SpellKit.load!(dictionary: malformed_dict)

      stats = SpellKit.stats

      # Valid entries that should load:
      # - hello	10000
      # - world	8000
      # - valid	2000
      # - another-valid	1500
      # - New York	5000 (multi-word terms now supported)
      # - cell culture	3000 (multi-word terms now supported)
      expect(stats["dictionary_size"]).to eq(6)

      # Verify they work
      expect(SpellKit.correct("helo")).to eq("hello")
      expect(SpellKit.correct("wrld")).to eq("world")
      expect(SpellKit.correct("newyork")).to eq("New York")
    end

    it "initializes skip counters to zero" do
      test_dict = File.expand_path("fixtures/test_unigrams.tsv", __dir__)
      SpellKit.load!(dictionary: test_dict)

      stats = SpellKit.stats

      # Clean dictionary should have zero skipped entries
      expect(stats["skipped_malformed"]).to eq(0)
      expect(stats["skipped_multiword"]).to eq(0)
      expect(stats["skipped_invalid_freq"]).to eq(0)
    end
  end

  describe "TSV parsing" do
    it "correctly handles tabs in term field vs delimiter tabs" do
      # Create a dictionary with proper tab delimiters
      dict_with_tabs = Tempfile.new(["dict", ".tsv"])
      dict_with_tabs.write("hello\t10000\n")
      dict_with_tabs.write("world\t8000\n")
      dict_with_tabs.close

      SpellKit.load!(dictionary: dict_with_tabs.path)

      stats = SpellKit.stats
      expect(stats["dictionary_size"]).to eq(2)
      expect(stats["skipped_malformed"]).to eq(0)

      dict_with_tabs.unlink
    end

    it "accepts space-separated entries (SymSpell format)" do
      # Space-separated format is now supported for SymSpell dictionaries
      space_dict = Tempfile.new(["space", ".tsv"])
      space_dict.write("hello 10000\n")  # Space separator (SymSpell format)
      space_dict.write("world 8000\n")   # Space separator (SymSpell format)
      space_dict.close

      SpellKit.load!(dictionary: space_dict.path)

      stats = SpellKit.stats
      # Both should load successfully
      expect(stats["dictionary_size"]).to eq(2)
      expect(stats["skipped_malformed"]).to eq(0)

      # Verify they work
      expect(SpellKit.correct?("hello")).to eq(true)
      expect(SpellKit.correct?("world")).to eq(true)

      space_dict.unlink
    end

    it "handles leading/trailing whitespace in fields" do
      # Test trimming behavior
      whitespace_dict = Tempfile.new(["whitespace", ".tsv"])
      whitespace_dict.write("  hello  \t  10000  \n")
      whitespace_dict.write("world\t8000\n")
      whitespace_dict.close

      SpellKit.load!(dictionary: whitespace_dict.path)

      stats = SpellKit.stats
      expect(stats["dictionary_size"]).to eq(2)

      # Verify trimmed term works
      expect(SpellKit.correct("helo")).to eq("hello")

      whitespace_dict.unlink
    end
  end

  describe "edge cases" do
    let(:edge_cases_dict) { File.expand_path("fixtures/edge_cases.tsv", __dir__) }

    it "handles empty lines as malformed" do
      SpellKit.load!(dictionary: edge_cases_dict)
      stats = SpellKit.stats

      # Edge cases file has:
      # - 1 valid entry (hello)
      # - 2 empty lines (malformed)
      # - 2 entries with empty terms after trim (malformed)
      # - 2 entries with missing frequency (malformed)
      expect(stats["dictionary_size"]).to eq(1)
      expect(stats["skipped_malformed"]).to eq(6)
    end

    it "rejects empty terms after trimming" do
      empty_term_dict = Tempfile.new(["empty_term", ".tsv"])
      empty_term_dict.write("\t1000\n")       # Empty term
      empty_term_dict.write("   \t2000\n")    # Whitespace-only term
      empty_term_dict.write("hello\t3000\n")  # Valid
      empty_term_dict.close

      SpellKit.load!(dictionary: empty_term_dict.path)
      stats = SpellKit.stats

      expect(stats["dictionary_size"]).to eq(1)
      expect(stats["skipped_malformed"]).to eq(2)

      # Verify we can use the valid entry
      expect(SpellKit.correct("helo")).to eq("hello")

      empty_term_dict.unlink
    end

    it "rejects empty frequencies after trimming" do
      empty_freq_dict = Tempfile.new(["empty_freq", ".tsv"])
      empty_freq_dict.write("hello\t\n")      # Empty frequency
      empty_freq_dict.write("world\t   \n")   # Whitespace-only frequency
      empty_freq_dict.write("test\t1000\n")   # Valid
      empty_freq_dict.close

      SpellKit.load!(dictionary: empty_freq_dict.path)
      stats = SpellKit.stats

      expect(stats["dictionary_size"]).to eq(1)
      expect(stats["skipped_malformed"]).to eq(2)

      empty_freq_dict.unlink
    end

    it "handles completely empty file" do
      empty_dict = Tempfile.new(["empty", ".tsv"])
      empty_dict.write("")
      empty_dict.close

      SpellKit.load!(dictionary: empty_dict.path)
      stats = SpellKit.stats

      expect(stats["dictionary_size"]).to eq(0)
      expect(stats["skipped_malformed"]).to eq(0)
      expect(stats["skipped_multiword"]).to eq(0)
      expect(stats["skipped_invalid_freq"]).to eq(0)

      empty_dict.unlink
    end

    it "handles file with valid and invalid entries" do
      invalid_dict = Tempfile.new(["invalid", ".tsv"])
      invalid_dict.write("New York\t1000\n")  # Valid - multi-word terms now supported
      invalid_dict.write("hello world\t2000\n")  # Valid - multi-word terms now supported
      invalid_dict.write("bad\tnot_a_number\n")  # Invalid freq
      invalid_dict.write("\t999\n")  # Empty term
      invalid_dict.close

      SpellKit.load!(dictionary: invalid_dict.path)
      stats = SpellKit.stats

      expect(stats["dictionary_size"]).to eq(2)  # New York and hello world
      expect(stats["skipped_multiword"]).to eq(0)  # Multi-word terms are now supported
      expect(stats["skipped_invalid_freq"]).to eq(1)
      expect(stats["skipped_malformed"]).to eq(1)

      invalid_dict.unlink
    end

    it "handles zero frequency correctly" do
      zero_dict = Tempfile.new(["zero", ".tsv"])
      zero_dict.write("hello\t0\n")
      zero_dict.write("world\t1000\n")
      zero_dict.close

      SpellKit.load!(dictionary: zero_dict.path)
      stats = SpellKit.stats

      # Zero is a valid u64, should load
      expect(stats["dictionary_size"]).to eq(2)
      expect(stats["skipped_invalid_freq"]).to eq(0)

      zero_dict.unlink
    end

    it "rejects negative frequencies" do
      negative_dict = Tempfile.new(["negative", ".tsv"])
      negative_dict.write("hello\t-1000\n")
      negative_dict.write("world\t1000\n")
      negative_dict.close

      SpellKit.load!(dictionary: negative_dict.path)
      stats = SpellKit.stats

      # Negative fails u64 parsing
      expect(stats["dictionary_size"]).to eq(1)
      expect(stats["skipped_invalid_freq"]).to eq(1)

      negative_dict.unlink
    end

    it "counts exact entries correctly with duplicates" do
      dup_dict = Tempfile.new(["dup", ".tsv"])
      dup_dict.write("hello\t1000\n")
      dup_dict.write("world\t2000\n")
      dup_dict.write("hello\t3000\n")  # Duplicate (will overwrite)
      dup_dict.close

      SpellKit.load!(dictionary: dup_dict.path)
      stats = SpellKit.stats

      # dictionary_size counts all attempts, not unique entries
      expect(stats["dictionary_size"]).to eq(3)

      # But only 2 unique words in the actual dictionary
      # Verify hello was loaded (last entry wins with freq 3000)
      expect(SpellKit.correct("helo")).to eq("hello")

      dup_dict.unlink
    end
  end
end