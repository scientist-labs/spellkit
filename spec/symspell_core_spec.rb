RSpec.describe "SymSpell Core (M1)" do
  let(:test_unigrams) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }

  before do
    SpellKit.load!(unigrams_path: test_unigrams, edit_distance: 1)
  end

  describe "basic functionality" do
    it "finds exact matches with distance 0" do
      suggestions = SpellKit.suggest("hello", 1)
      expect(suggestions.first["distance"]).to eq(0)
      expect(suggestions.first["term"]).to eq("hello")
    end

    it "finds edit distance 1 matches" do
      suggestions = SpellKit.suggest("helo", 3)
      expect(suggestions).to all(include("distance" => 1))
      # Should include both "hello" and "help" at distance 1
      terms = suggestions.map { |s| s["term"] }
      expect(terms).to include("hello", "help", "hell")
    end

    it "orders by distance then frequency" do
      suggestions = SpellKit.suggest("helo", 3)
      # All distance 1, ordered by frequency
      expect(suggestions[0]["term"]).to eq("hello") # freq: 10000
      expect(suggestions[0]["freq"]).to eq(10000)
      expect(suggestions[1]["term"]).to eq("help")  # freq: 3000
      expect(suggestions[1]["freq"]).to eq(3000)
    end

    it "returns empty for words beyond edit distance" do
      suggestions = SpellKit.suggest("zzzzz", 5)
      expect(suggestions).to be_empty
    end
  end
end