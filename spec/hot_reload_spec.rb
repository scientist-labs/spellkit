RSpec.describe "Hot Reload & Manifests (M3)" do
  let(:test_unigrams) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }
  let(:temp_unigrams) { File.expand_path("fixtures/temp_unigrams.tsv", __dir__) }
  let(:symbols_file) { File.expand_path("fixtures/symbols.txt", __dir__) }

  after do
    FileUtils.rm_f(temp_unigrams)
  end

  describe "hot reload" do
    it "can reload dictionary without restart" do
      # Initial load
      SpellKit.load!(dictionary: test_unigrams)

      # Verify initial state
      suggestions = SpellKit.suggestions("helo", 1)
      expect(suggestions.first["term"]).to eq("hello")

      # Create new dictionary with different content
      File.write(temp_unigrams, "help\t50000\nworld\t30000")

      # Reload with new dictionary
      SpellKit.load!(dictionary: temp_unigrams)

      # Verify new state - "help" should now be the only suggestion
      suggestions = SpellKit.suggestions("helo", 1)
      expect(suggestions.first["term"]).to eq("help")
      expect(suggestions.first["freq"]).to eq(50000)
    end
  end

  describe "stats API" do
    before do
      SpellKit.load!(dictionary: test_unigrams)
    end

    it "provides statistics" do
      stats = SpellKit.stats
      expect(stats["loaded"]).to be true
      expect(stats["dictionary_size"]).to eq(20)
      expect(stats["edit_distance"]).to eq(1)
      expect(stats["loaded_at"]).to be_a(Integer)
    end
  end

  describe "healthcheck API" do
    it "succeeds when properly loaded" do
      SpellKit.load!(dictionary: test_unigrams)
      expect { SpellKit.healthcheck }.not_to raise_error
    end
  end
end