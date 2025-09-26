RSpec.describe SpellKit do
  let(:test_unigrams) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }

  it "has a version number" do
    expect(SpellKit::VERSION).not_to be nil
  end

  describe ".load!" do
    it "loads the dictionary" do
      expect {
        SpellKit.load!(dictionary: test_unigrams)
      }.not_to raise_error
    end

    it "accepts edit distance parameter" do
      expect {
        SpellKit.load!(dictionary: test_unigrams, edit_distance: 2)
      }.not_to raise_error
    end
  end

  describe ".suggest" do
    before do
      SpellKit.load!(dictionary: test_unigrams)
    end

    it "returns suggestions for misspelled words" do
      suggestions = SpellKit.suggest("helo", 3)
      expect(suggestions).to be_an(Array)
      expect(suggestions.first).to include("term", "distance", "freq")
      # "hello" comes first because it has higher frequency than "help"
      expect(suggestions.first["term"]).to eq("hello")
      expect(suggestions.first["distance"]).to eq(1)
      expect(suggestions.first["freq"]).to eq(10000)
    end

    it "returns exact match with distance 0" do
      suggestions = SpellKit.suggest("hello", 1)
      expect(suggestions.first["term"]).to eq("hello")
      expect(suggestions.first["distance"]).to eq(0)
    end

    it "returns empty array for words too far from dictionary" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 1)
      suggestions = SpellKit.suggest("zzzzzz", 5)
      expect(suggestions).to eq([])
    end
  end

  describe ".correct_if_unknown" do
    before do
      SpellKit.load!(dictionary: test_unigrams)
    end

    it "corrects misspelled words" do
      expect(SpellKit.correct_if_unknown("lyssis")).to eq("lysis")
    end

    it "preserves correctly spelled words" do
      expect(SpellKit.correct_if_unknown("hello")).to eq("hello")
    end

    it "returns original word if no good correction found" do
      expect(SpellKit.correct_if_unknown("zzzzzz")).to eq("zzzzzz")
    end
  end
end
