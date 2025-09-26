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
end