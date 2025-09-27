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

  describe ".correct?" do
    before do
      SpellKit.load!(dictionary: test_unigrams)
    end

    it "returns true for correctly spelled words" do
      expect(SpellKit.correct?("hello")).to be true
      expect(SpellKit.correct?("world")).to be true
      expect(SpellKit.correct?("lysis")).to be true
    end

    it "returns false for misspelled words" do
      expect(SpellKit.correct?("helo")).to be false
      expect(SpellKit.correct?("wrld")).to be false
      expect(SpellKit.correct?("lyssis")).to be false
    end

    it "returns false for words not in dictionary" do
      expect(SpellKit.correct?("zzzzzz")).to be false
      expect(SpellKit.correct?("asdfgh")).to be false
    end

    it "is case insensitive" do
      expect(SpellKit.correct?("HELLO")).to be true
      expect(SpellKit.correct?("Hello")).to be true
      expect(SpellKit.correct?("HeLLo")).to be true
    end

    it "raises error for nil word" do
      expect {
        SpellKit.correct?(nil)
      }.to raise_error(SpellKit::InvalidArgumentError, "word cannot be nil")
    end

    it "raises error for empty word" do
      expect {
        SpellKit.correct?("")
      }.to raise_error(SpellKit::InvalidArgumentError, "word cannot be empty")
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

    describe "frequency threshold" do
      it "rejects corrections below absolute frequency threshold" do
        # "incubation" has frequency 600 in test dictionary
        # Set threshold to 1000, so 600 < 1000 = rejection
        SpellKit.load!(dictionary: test_unigrams, frequency_threshold: 1000.0)

        # "incubatio" -> "incubation" (distance 1, freq 600)
        # Should NOT correct because 600 < 1000
        expect(SpellKit.correct_if_unknown("incubatio")).to eq("incubatio")
      end

      it "accepts corrections above absolute frequency threshold" do
        # "hello" has frequency 10000 in test dictionary
        # Set threshold to 1000, so 10000 >= 1000 = acceptance
        SpellKit.load!(dictionary: test_unigrams, frequency_threshold: 1000.0)

        # "helo" -> "hello" (distance 1, freq 10000)
        # Should correct because 10000 >= 1000
        expect(SpellKit.correct_if_unknown("helo")).to eq("hello")
      end

      it "uses default threshold of 10.0" do
        SpellKit.load!(dictionary: test_unigrams)

        # All words in test dictionary have freq >= 10, so corrections should work
        expect(SpellKit.correct_if_unknown("helo")).to eq("hello")
        expect(SpellKit.correct_if_unknown("incubatio")).to eq("incubation")
      end
    end
  end
end
