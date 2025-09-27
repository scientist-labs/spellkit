require "tempfile"

RSpec.describe "Canonical Form Preservation" do
  let(:test_dict) do
    dict = Tempfile.new(["canonical", ".tsv"])
    dict.write("NASA\t10000\n")
    dict.write("New York\t5000\n")
    dict.write("iPhone\t8000\n")
    dict.write("McDonald's\t6000\n")
    dict.write("FooBar\t3000\n")
    dict.close
    dict
  end

  after do
    test_dict.unlink
  end

  describe "single word correction" do
    before do
      SpellKit.load!(dictionary: test_dict.path)
    end

    it "preserves uppercase (NASA)" do
      expect(SpellKit.correct("nasa")).to eq("NASA")
      expect(SpellKit.correct("NASA")).to eq("NASA")
      expect(SpellKit.correct("Nasa")).to eq("NASA")
    end

    it "preserves mixed case (iPhone)" do
      expect(SpellKit.correct("iphone")).to eq("iPhone")
      expect(SpellKit.correct("IPHONE")).to eq("iPhone")
      expect(SpellKit.correct("IPhone")).to eq("iPhone")
    end

    it "preserves mixed case (FooBar)" do
      expect(SpellKit.correct("foobar")).to eq("FooBar")
      expect(SpellKit.correct("FOOBAR")).to eq("FooBar")
      expect(SpellKit.correct("Foobar")).to eq("FooBar")
    end

    it "preserves apostrophes (McDonald's)" do
      expect(SpellKit.correct("mcdonalds")).to eq("McDonald's")
      expect(SpellKit.correct("MCDONALDS")).to eq("McDonald's")
    end

    it "preserves whitespace (New York)" do
      # Input "newyork" (normalized form) returns canonical "New York"
      expect(SpellKit.correct("newyork")).to eq("New York")
      expect(SpellKit.correct("NEWYORK")).to eq("New York")
      expect(SpellKit.correct("NewYork")).to eq("New York")
    end

    it "returns canonical form even for exact normalized matches" do
      # When user types lowercase but dictionary has mixed case
      expect(SpellKit.correct?("nasa")).to eq(true)
      expect(SpellKit.correct("nasa")).to eq("NASA")
    end
  end

  describe "suggestions" do
    before do
      SpellKit.load!(dictionary: test_dict.path)
    end

    it "returns canonical forms in suggestions" do
      suggestions = SpellKit.suggestions("nasa", 1)
      expect(suggestions.first["term"]).to eq("NASA")
    end

    it "preserves whitespace in suggestions" do
      suggestions = SpellKit.suggestions("newyork", 1)
      expect(suggestions.first["term"]).to eq("New York")
    end

    it "preserves mixed case in suggestions" do
      suggestions = SpellKit.suggestions("iphone", 1)
      expect(suggestions.first["term"]).to eq("iPhone")
    end

    it "preserves apostrophes in suggestions" do
      suggestions = SpellKit.suggestions("mcdonalds", 1)
      expect(suggestions.first["term"]).to eq("McDonald's")
    end
  end

  describe "batch correction" do
    before do
      SpellKit.load!(dictionary: test_dict.path)
    end

    it "preserves canonical forms in batch operations" do
      tokens = %w[nasa newyork iphone mcdonalds foobar]
      corrected = SpellKit.correct_tokens(tokens)

      expect(corrected).to eq([
        "NASA",
        "New York",
        "iPhone",
        "McDonald's",
        "FooBar"
      ])
    end

    it "works with mixed case inputs" do
      tokens = %w[NASA newyork IPHONE McDonalds]
      corrected = SpellKit.correct_tokens(tokens)

      expect(corrected).to eq([
        "NASA",
        "New York",
        "iPhone",
        "McDonald's"
      ])
    end
  end

  describe "with guards enabled" do
    before do
      SpellKit.load!(dictionary: test_dict.path)
    end

    it "preserves canonical forms with guard: :domain" do
      expect(SpellKit.correct("nasa", guard: :domain)).to eq("NASA")
      expect(SpellKit.correct("newyork", guard: :domain)).to eq("New York")
      expect(SpellKit.correct("iphone", guard: :domain)).to eq("iPhone")
    end

    it "preserves canonical forms in batch with guard: :domain" do
      tokens = %w[nasa iphone foobar]
      corrected = SpellKit.correct_tokens(tokens, guard: :domain)

      expect(corrected).to eq(["NASA", "iPhone", "FooBar"])
    end
  end

  describe "integration with DEFAULT_DICTIONARY_URL" do
    before do
      SpellKit.load!(dictionary: SpellKit::DEFAULT_DICTIONARY_URL)
    end

    it "returns canonical forms from SymSpell dictionary", :integration do
      # SymSpell en-80k dictionary has lowercase entries, so this tests that lowercase is preserved
      expect(SpellKit.correct("hello")).to eq("hello")
      expect(SpellKit.correct("world")).to eq("world")

      # These should be unchanged
      expect(SpellKit.correct("HELLO")).to eq("hello")  # normalizes to lowercase canonical form
    end
  end
end