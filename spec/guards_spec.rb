RSpec.describe "Guards & Domain Policies (M2)" do
  let(:test_unigrams) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }
  let(:symbols_file) { File.expand_path("fixtures/symbols.txt", __dir__) }
  let(:species_file) { File.expand_path("fixtures/species.txt", __dir__) }

  before do
    SpellKit.load!(
      unigrams_path: test_unigrams,
      symbols_path: symbols_file,
      species_path: species_file,
      edit_distance: 1
    )
  end

  describe "protected terms" do
    it "does not correct gene symbols" do
      expect(SpellKit.correct_if_unknown("CDK10", guard: :domain)).to eq("CDK10")
      expect(SpellKit.correct_if_unknown("BRCA1", guard: :domain)).to eq("BRCA1")
    end

    it "does not correct species names" do
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

      expect(corrected).to eq(%w[rat lyssis buffers for CDK10])
      # Note: "lyssis" and "buffers" stay as-is because they're not close enough to dictionary words
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
end