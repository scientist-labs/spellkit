require "tempfile"

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

  describe ".suggestions" do
    before do
      SpellKit.load!(dictionary: test_unigrams)
    end

    it "returns suggestions for misspelled words" do
      suggestions = SpellKit.suggestions("helo", 3)
      expect(suggestions).to be_an(Array)
      expect(suggestions.first).to include("term", "distance", "freq")
      # "hello" comes first because it has higher frequency than "help"
      expect(suggestions.first["term"]).to eq("hello")
      expect(suggestions.first["distance"]).to eq(1)
      expect(suggestions.first["freq"]).to eq(10000)
    end

    it "returns exact match with distance 0" do
      suggestions = SpellKit.suggestions("hello", 1)
      expect(suggestions.first["term"]).to eq("hello")
      expect(suggestions.first["distance"]).to eq(0)
    end

    it "returns empty array for words too far from dictionary" do
      SpellKit.load!(dictionary: test_unigrams, edit_distance: 1)
      suggestions = SpellKit.suggestions("zzzzzz", 5)
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

  describe ".correct" do
    before do
      SpellKit.load!(dictionary: test_unigrams)
    end

    it "corrects misspelled words" do
      expect(SpellKit.correct("lyssis")).to eq("lysis")
    end

    it "preserves correctly spelled words" do
      expect(SpellKit.correct("hello")).to eq("hello")
    end

    it "returns original word if no good correction found" do
      expect(SpellKit.correct("zzzzzz")).to eq("zzzzzz")
    end

    it "corrects single-character words" do
      dict = Tempfile.new(["single", ".tsv"])
      dict.write("a\t10000\n")
      dict.write("i\t8000\n")
      dict.write("o\t6000\n")
      dict.close

      SpellKit.load!(dictionary: dict.path, edit_distance: 1)

      # Verify single-character corrections work (was previously broken)
      expect(SpellKit.correct("x")).to eq("a")  # Should correct to highest-frequency match
      expect(SpellKit.suggestions("j", 5).length).to be > 0  # Should find suggestions

      dict.unlink
    end

    describe "frequency threshold" do
      it "rejects corrections below absolute frequency threshold" do
        # "incubation" has frequency 600 in test dictionary
        # Set threshold to 1000, so 600 < 1000 = rejection
        SpellKit.load!(dictionary: test_unigrams, frequency_threshold: 1000.0)

        # "incubatio" -> "incubation" (distance 1, freq 600)
        # Should NOT correct because 600 < 1000
        expect(SpellKit.correct("incubatio")).to eq("incubatio")
      end

      it "accepts corrections above absolute frequency threshold" do
        # "hello" has frequency 10000 in test dictionary
        # Set threshold to 1000, so 10000 >= 1000 = acceptance
        SpellKit.load!(dictionary: test_unigrams, frequency_threshold: 1000.0)

        # "helo" -> "hello" (distance 1, freq 10000)
        # Should correct because 10000 >= 1000
        expect(SpellKit.correct("helo")).to eq("hello")
      end

      it "uses default threshold of 10.0" do
        SpellKit.load!(dictionary: test_unigrams)

        # All words in test dictionary have freq >= 10, so corrections should work
        expect(SpellKit.correct("helo")).to eq("hello")
        expect(SpellKit.correct("incubatio")).to eq("incubation")
      end
    end

    describe "edit distance" do
      it "corrects distance-1 typos with edit_distance: 1" do
        SpellKit.load!(dictionary: test_unigrams, edit_distance: 1)

        # "helo" -> "hello" (distance 1: insert 'l')
        expect(SpellKit.correct("helo")).to eq("hello")
        # "tst" -> "test" (distance 1: insert 'e')
        expect(SpellKit.correct("tst")).to eq("test")
      end

      it "does NOT correct distance-2 typos with edit_distance: 1" do
        SpellKit.load!(dictionary: test_unigrams, edit_distance: 1)

        # "hllo" -> "hello" would be distance 1, but let's use distance 2
        # "heo" -> "hello" (distance 2: insert 'l' twice)
        # Since SymSpell with edit_distance: 1 won't find distance-2 matches,
        # the word should remain unchanged
        expect(SpellKit.correct("heo")).to eq("heo")
        # "st" -> "test" (distance 2: insert 't' and 'e')
        expect(SpellKit.correct("st")).to eq("st")
      end

      it "corrects distance-2 typos with edit_distance: 2" do
        SpellKit.load!(dictionary: test_unigrams, edit_distance: 2)

        # "heo" -> "hello" (distance 2: insert 'l' twice)
        expect(SpellKit.correct("heo")).to eq("hello")
        # "st" -> "test" (distance 2: insert 't' and 'e')
        expect(SpellKit.correct("st")).to eq("test")
      end

      it "corrects distance-2 typos in batch with edit_distance: 2" do
        SpellKit.load!(dictionary: test_unigrams, edit_distance: 2)

        tokens = %w[heo st helo tst]
        corrected = SpellKit.correct_tokens(tokens)

        # "heo" -> "hello" (distance 2)
        # "st" -> "test" (distance 2)
        # "helo" -> "hello" (distance 1)
        # "tst" -> "test" (distance 1)
        expect(corrected).to eq(%w[hello test hello test])
      end

      it "does NOT correct distance-2 typos in batch with edit_distance: 1" do
        SpellKit.load!(dictionary: test_unigrams, edit_distance: 1)

        tokens = %w[heo st helo tst]
        corrected = SpellKit.correct_tokens(tokens)

        # "heo" -> "heo" (distance 2, not corrected)
        # "st" -> "st" (distance 2, not corrected)
        # "helo" -> "hello" (distance 1, corrected)
        # "tst" -> "test" (distance 1, corrected)
        expect(corrected).to eq(%w[heo st hello test])
      end

      it "respects frequency threshold with edit_distance: 2" do
        # "incubation" has frequency 600 in test dictionary
        # Set threshold to 1000, so 600 < 1000 = rejection
        SpellKit.load!(dictionary: test_unigrams, edit_distance: 2, frequency_threshold: 1000.0)

        # Even with edit_distance: 2, frequency threshold should still apply
        # "incubatio" -> "incubation" (distance 1, freq 600)
        # Should NOT correct because 600 < 1000
        expect(SpellKit.correct("incubatio")).to eq("incubatio")

        # But high-frequency corrections should still work
        # "heo" -> "hello" (distance 2, freq 10000 > 1000)
        expect(SpellKit.correct("heo")).to eq("hello")
      end

      it "prefers closer matches when multiple distances available" do
        SpellKit.load!(dictionary: test_unigrams, edit_distance: 2)

        # "helo" has both distance-1 match ("hello") and potentially distance-2 matches
        # Should prefer distance-1 "hello" over any distance-2 alternatives
        # SymSpell orders by distance first, then frequency, so this should work
        expect(SpellKit.correct("helo")).to eq("hello")
      end

      it "still short-circuits on exact matches with edit_distance: 2" do
        SpellKit.load!(dictionary: test_unigrams, edit_distance: 2)

        # "hello" is exact match (distance 0) - should return as-is
        expect(SpellKit.correct("hello")).to eq("hello")
        expect(SpellKit.correct("test")).to eq("test")
      end
    end
  end
end
