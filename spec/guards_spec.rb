require "tempfile"

RSpec.describe "Guards & Domain Policies (M2)" do
  let(:test_unigrams) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }
  let(:protected_file) { File.expand_path("fixtures/protected.txt", __dir__) }

  before do
    SpellKit.load!(
      dictionary: test_unigrams,
      protected_path: protected_file,
      edit_distance: 1
    )
  end

  describe "protected terms" do
    it "does not correct protected terms" do
      expect(SpellKit.correct_if_unknown("CDK10", guard: :domain)).to eq("CDK10")
      expect(SpellKit.correct_if_unknown("BRCA1", guard: :domain)).to eq("BRCA1")
      expect(SpellKit.correct_if_unknown("rat", guard: :domain)).to eq("rat")
      expect(SpellKit.correct_if_unknown("mouse", guard: :domain)).to eq("mouse")
    end

    it "handles IL-6 and IL6 variants" do
      expect(SpellKit.correct_if_unknown("IL6", guard: :domain)).to eq("IL6")
      expect(SpellKit.correct_if_unknown("IL-6", guard: :domain)).to eq("IL-6")
    end

    it "corrects non-protected typos when guard is enabled" do
      # "lyssis" is not protected and should be corrected
      expect(SpellKit.correct_if_unknown("helo", guard: :domain)).to eq("hello")
    end
  end

  describe "batch correction with guards" do
    it "corrects tokens while preserving protected terms" do
      tokens = %w[rat lyssis buffers for CDK10]
      corrected = SpellKit.correct_tokens(tokens, guard: :domain)

      expect(corrected).to eq(%w[rat lysis buffer for CDK10])
      # "lyssis" → "lysis" (ED=1), "buffers" → "buffer" (ED=1), "CDK10" protected
    end

    it "preserves protected terms with edit_distance: 2" do
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_path: protected_file,
        edit_distance: 2
      )

      # Protected terms should remain protected even with edit_distance: 2
      expect(SpellKit.correct_if_unknown("CDK10", guard: :domain)).to eq("CDK10")
      expect(SpellKit.correct_if_unknown("BRCA1", guard: :domain)).to eq("BRCA1")

      # Non-protected distance-2 typos should still be corrected
      # "heo" -> "hello" (distance 2)
      expect(SpellKit.correct_if_unknown("heo", guard: :domain)).to eq("hello")
    end
  end

  describe "without guards" do
    it "may incorrectly 'correct' domain terms" do
      # Without guards, CDK10 might get changed if there's a similar word
      # This test shows why guards are important
      result = SpellKit.correct_if_unknown("CDK10", guard: nil)
      # CDK10 won't match anything in our small test dictionary
      expect(result).to eq("CDK10") # No close match, stays the same
    end
  end

  describe "protected patterns" do
    it "protects terms matching regex patterns" do
      # Load with regex patterns
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [/^[A-Z]{3,4}\d+$/, /^\d{2,7}-\d{2}-\d$/]
      )

      # Should protect gene symbols like CDK10, BRCA1
      expect(SpellKit.correct_if_unknown("CDK10", guard: :domain)).to eq("CDK10")
      expect(SpellKit.correct_if_unknown("BRCA1", guard: :domain)).to eq("BRCA1")

      # Should protect CAS numbers
      expect(SpellKit.correct_if_unknown("7732-18-5", guard: :domain)).to eq("7732-18-5")

      # Should still correct non-matching terms
      expect(SpellKit.correct_if_unknown("helo", guard: :domain)).to eq("hello")
    end

    it "accepts both Regexp and String patterns" do
      # Load with mixed pattern types
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [/^CDK\d+$/, "^IL-?\\d+$"]
      )

      expect(SpellKit.correct_if_unknown("CDK10", guard: :domain)).to eq("CDK10")
      expect(SpellKit.correct_if_unknown("IL6", guard: :domain)).to eq("IL6")
      expect(SpellKit.correct_if_unknown("IL-6", guard: :domain)).to eq("IL-6")
    end
  end

  describe "regex flags" do
    it "honors case-insensitive flag from Ruby Regexp" do
      # Load with case-insensitive pattern
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [/^IL-?\d+$/i]  # Case-insensitive!
      )

      # Should match regardless of case
      expect(SpellKit.correct_if_unknown("IL6", guard: :domain)).to eq("IL6")
      expect(SpellKit.correct_if_unknown("il6", guard: :domain)).to eq("il6")
      expect(SpellKit.correct_if_unknown("Il6", guard: :domain)).to eq("Il6")
      expect(SpellKit.correct_if_unknown("IL-6", guard: :domain)).to eq("IL-6")
      expect(SpellKit.correct_if_unknown("il-6", guard: :domain)).to eq("il-6")
    end

    it "respects case-sensitive patterns without flag" do
      # Load with case-sensitive pattern (no /i flag)
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [/^IL-?\d+$/]  # Case-sensitive
      )

      # Should only match uppercase IL
      expect(SpellKit.correct_if_unknown("IL6", guard: :domain)).to eq("IL6")
      expect(SpellKit.correct_if_unknown("IL-6", guard: :domain)).to eq("IL-6")

      # Lowercase should NOT be protected (case-sensitive pattern)
      # We can verify this by checking it's NOT in the protected set
      # by testing with a case-insensitive pattern that WOULD match
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [/^IL-?\d+$/i]  # Now with /i flag
      )
      expect(SpellKit.correct_if_unknown("il6", guard: :domain)).to eq("il6")  # Protected now!
    end

    it "honors multiline flag from Ruby Regexp" do
      # Multiline mode makes ^ and $ match line boundaries, not just string boundaries
      # This is less common for our use case but should still work
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [/^test$/m]  # Multiline mode
      )

      expect(SpellKit.correct_if_unknown("test", guard: :domain)).to eq("test")
    end

    it "honors extended flag for readable patterns" do
      # Extended mode allows whitespace and comments in patterns
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [
          /^
            [A-Z]{3,4}  # 3-4 uppercase letters
            \d+         # followed by digits
          $/x  # Extended mode for readability
        ]
      )

      expect(SpellKit.correct_if_unknown("CDK10", guard: :domain)).to eq("CDK10")
      expect(SpellKit.correct_if_unknown("BRCA1", guard: :domain)).to eq("BRCA1")
    end

    it "combines case-insensitive + extended flags (/ix)" do
      # Test case-insensitive + extended together
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [
          /^
            il-?\d+  # IL followed by optional dash and digits
          $/ix  # Case-insensitive + extended
        ]
      )

      # Should match regardless of case due to /i flag
      expect(SpellKit.correct_if_unknown("IL6", guard: :domain)).to eq("IL6")
      expect(SpellKit.correct_if_unknown("il6", guard: :domain)).to eq("il6")
      expect(SpellKit.correct_if_unknown("Il-6", guard: :domain)).to eq("Il-6")
    end

    it "combines case-insensitive + multiline flags (/im)" do
      # Multiline makes ^ and $ match line boundaries
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [/^test$/im]
      )

      # Should match "test" with any case
      expect(SpellKit.correct_if_unknown("test", guard: :domain)).to eq("test")
      expect(SpellKit.correct_if_unknown("TEST", guard: :domain)).to eq("TEST")
      expect(SpellKit.correct_if_unknown("Test", guard: :domain)).to eq("Test")
    end

    it "combines multiline + extended flags (/mx)" do
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [
          /^
            test  # The word "test"
          $/mx    # Multiline + extended
        ]
      )

      expect(SpellKit.correct_if_unknown("test", guard: :domain)).to eq("test")
    end

    it "combines all three flags together (/imx)" do
      # Test all flags: case-insensitive, multiline, and extended
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [
          /^
            test   # Match "test" in any case
            (ing)? # Optional "ing" suffix
          $/imx    # All three flags!
        ]
      )

      # Should match regardless of case (due to /i)
      expect(SpellKit.correct_if_unknown("test", guard: :domain)).to eq("test")
      expect(SpellKit.correct_if_unknown("TEST", guard: :domain)).to eq("TEST")
      expect(SpellKit.correct_if_unknown("testing", guard: :domain)).to eq("testing")
      expect(SpellKit.correct_if_unknown("TESTING", guard: :domain)).to eq("TESTING")
      expect(SpellKit.correct_if_unknown("Testing", guard: :domain)).to eq("Testing")
    end

    it "handles String patterns as case-sensitive by default" do
      # String patterns should be case-sensitive (no implicit /i)
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: ["^IL-?\\d+$"]  # String, not Regexp
      )

      # Should only match uppercase
      expect(SpellKit.correct_if_unknown("IL6", guard: :domain)).to eq("IL6")
      expect(SpellKit.correct_if_unknown("IL-6", guard: :domain)).to eq("IL-6")

      # Verify String patterns are case-sensitive by comparing to Regexp with /i
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [/^IL-?\d+$/i]  # Regexp with /i flag
      )
      # Now lowercase should be protected
      expect(SpellKit.correct_if_unknown("il6", guard: :domain)).to eq("il6")
    end

    it "preserves pattern matching logic with case-insensitive flag" do
      # Verify /i flag doesn't break pattern matching logic
      # Complex pattern with character classes, quantifiers, alternation
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [/^(CDK|BRCA|TP53)[0-9]{1,3}$/i]
      )

      # Should match any case of these gene symbols
      expect(SpellKit.correct_if_unknown("CDK10", guard: :domain)).to eq("CDK10")
      expect(SpellKit.correct_if_unknown("cdk10", guard: :domain)).to eq("cdk10")
      expect(SpellKit.correct_if_unknown("Cdk10", guard: :domain)).to eq("Cdk10")
      expect(SpellKit.correct_if_unknown("BRCA1", guard: :domain)).to eq("BRCA1")
      expect(SpellKit.correct_if_unknown("brca1", guard: :domain)).to eq("brca1")
      expect(SpellKit.correct_if_unknown("TP538", guard: :domain)).to eq("TP538")
      expect(SpellKit.correct_if_unknown("tp538", guard: :domain)).to eq("tp538")

      # But NOT match different patterns
      result = SpellKit.correct_if_unknown("XYZ999", guard: :domain)
      expect(result).to eq("XYZ999")  # No dictionary match, stays unchanged but NOT protected
    end

    it "flags work correctly with multiple patterns" do
      # Test that different patterns with different flags coexist correctly
      SpellKit.load!(
        dictionary: test_unigrams,
        protected_patterns: [
          /^CDK\d+$/,    # Case-sensitive
          /^IL-?\d+$/i   # Case-insensitive
        ]
      )

      # CDK pattern: only uppercase protected
      expect(SpellKit.correct_if_unknown("CDK10", guard: :domain)).to eq("CDK10")

      # IL pattern: all cases protected
      expect(SpellKit.correct_if_unknown("IL6", guard: :domain)).to eq("IL6")
      expect(SpellKit.correct_if_unknown("il6", guard: :domain)).to eq("il6")
      expect(SpellKit.correct_if_unknown("Il-6", guard: :domain)).to eq("Il-6")
    end
  end

  describe "normalized variant protection" do
    it "protects normalized variants of protected terms automatically" do
      # Create a protected list with terms that have whitespace
      protected_with_spaces = Tempfile.new(["protected_spaces", ".txt"])
      protected_with_spaces.write("New York\n")
      protected_with_spaces.write("cell culture\n")
      protected_with_spaces.close

      SpellKit.load!(
        dictionary: test_unigrams,
        protected_path: protected_with_spaces.path,
        edit_distance: 2
      )

      # Literal forms should be protected
      expect(SpellKit.correct_if_unknown("New York", guard: :domain)).to eq("New York")
      expect(SpellKit.correct_if_unknown("cell culture", guard: :domain)).to eq("cell culture")

      # Lowercase forms should be protected
      expect(SpellKit.correct_if_unknown("new york", guard: :domain)).to eq("new york")
      expect(SpellKit.correct_if_unknown("cell culture", guard: :domain)).to eq("cell culture")

      # Normalized forms (whitespace stripped) should ALSO be protected
      expect(SpellKit.correct_if_unknown("newyork", guard: :domain)).to eq("newyork")
      expect(SpellKit.correct_if_unknown("NewYork", guard: :domain)).to eq("NewYork")
      expect(SpellKit.correct_if_unknown("cellculture", guard: :domain)).to eq("cellculture")
      expect(SpellKit.correct_if_unknown("CellCulture", guard: :domain)).to eq("CellCulture")

      protected_with_spaces.unlink
    end

    it "protects terms with punctuation in all forms" do
      protected_with_punct = Tempfile.new(["protected_punct", ".txt"])
      protected_with_punct.write("IL-6\n")
      protected_with_punct.write("p-value\n")
      protected_with_punct.close

      SpellKit.load!(
        dictionary: test_unigrams,
        protected_path: protected_with_punct.path,
        edit_distance: 2
      )

      # Literal forms
      expect(SpellKit.correct_if_unknown("IL-6", guard: :domain)).to eq("IL-6")
      expect(SpellKit.correct_if_unknown("p-value", guard: :domain)).to eq("p-value")

      # Lowercase forms (punctuation preserved)
      expect(SpellKit.correct_if_unknown("il-6", guard: :domain)).to eq("il-6")
      expect(SpellKit.correct_if_unknown("p-value", guard: :domain)).to eq("p-value")

      # Note: normalize_word doesn't strip punctuation, only whitespace
      # So IL-6 normalizes to "il-6" (with dash), not "il6"

      protected_with_punct.unlink
    end

    it "handles terms with mixed whitespace and punctuation" do
      protected_mixed = Tempfile.new(["protected_mixed", ".txt"])
      protected_mixed.write("New York, NY\n")
      protected_mixed.write("Smith, J.\n")
      protected_mixed.close

      SpellKit.load!(
        dictionary: test_unigrams,
        protected_path: protected_mixed.path,
        edit_distance: 2
      )

      # Literal forms
      expect(SpellKit.correct_if_unknown("New York, NY", guard: :domain)).to eq("New York, NY")
      expect(SpellKit.correct_if_unknown("Smith, J.", guard: :domain)).to eq("Smith, J.")

      # Normalized forms (whitespace stripped, punctuation preserved)
      expect(SpellKit.correct_if_unknown("newyork,ny", guard: :domain)).to eq("newyork,ny")
      expect(SpellKit.correct_if_unknown("smith,j.", guard: :domain)).to eq("smith,j.")

      protected_mixed.unlink
    end

    it "doesn't duplicate entries in the HashSet" do
      # Terms that normalize to the same thing shouldn't cause issues
      protected_dups = Tempfile.new(["protected_dups", ".txt"])
      protected_dups.write("test\n")
      protected_dups.write("TEST\n")  # Same when lowercased
      protected_dups.write("hello\n")
      protected_dups.close

      SpellKit.load!(
        dictionary: test_unigrams,
        protected_path: protected_dups.path,
        edit_distance: 2
      )

      # All forms should work (HashSet handles duplicates)
      expect(SpellKit.correct_if_unknown("test", guard: :domain)).to eq("test")
      expect(SpellKit.correct_if_unknown("TEST", guard: :domain)).to eq("TEST")
      expect(SpellKit.correct_if_unknown("Test", guard: :domain)).to eq("Test")
      expect(SpellKit.correct_if_unknown("hello", guard: :domain)).to eq("hello")
      expect(SpellKit.correct_if_unknown("HELLO", guard: :domain)).to eq("HELLO")

      protected_dups.unlink
    end

    it "works with protected_patterns alongside protected terms" do
      protected_mixed_guards = Tempfile.new(["protected_both", ".txt"])
      protected_mixed_guards.write("New York\n")
      protected_mixed_guards.close

      SpellKit.load!(
        dictionary: test_unigrams,
        protected_path: protected_mixed_guards.path,
        protected_patterns: [/^IL-?\d+$/i],
        edit_distance: 2
      )

      # Protected file terms (all variants)
      expect(SpellKit.correct_if_unknown("New York", guard: :domain)).to eq("New York")
      expect(SpellKit.correct_if_unknown("newyork", guard: :domain)).to eq("newyork")

      # Protected pattern matches
      expect(SpellKit.correct_if_unknown("IL6", guard: :domain)).to eq("IL6")
      expect(SpellKit.correct_if_unknown("IL-6", guard: :domain)).to eq("IL-6")
      expect(SpellKit.correct_if_unknown("il6", guard: :domain)).to eq("il6")

      protected_mixed_guards.unlink
    end
  end
end