RSpec.describe "Multiple Instances" do
  let(:test_unigrams) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }
  let(:species_dict) { File.expand_path("fixtures/species.txt", __dir__) }
  let(:symbols_dict) { File.expand_path("fixtures/symbols.txt", __dir__) }

  before(:all) do
    File.write(File.expand_path("fixtures/species.txt", __dir__), <<~DICT)
      mouse\t10000
      rat\t9000
      human\t8000
      monkey\t5000
      zebrafish\t3000
    DICT

    File.write(File.expand_path("fixtures/symbols.txt", __dir__), <<~DICT)
      CDK10\t5000
      BRCA1\t4000
      TP53\t3000
      EGFR\t2000
    DICT
  end

  after(:all) do
    FileUtils.rm_f(File.expand_path("fixtures/species.txt", __dir__))
    FileUtils.rm_f(File.expand_path("fixtures/symbols.txt", __dir__))
  end

  describe "independent instances" do
    it "allows multiple checkers with different dictionaries" do
      species_checker = SpellKit::Checker.new
      species_checker.load!(dictionary: species_dict)

      symbols_checker = SpellKit::Checker.new
      symbols_checker.load!(dictionary: symbols_dict)

      species_stats = species_checker.stats
      symbols_stats = symbols_checker.stats

      expect(species_stats["dictionary_size"]).to eq(5)
      expect(symbols_stats["dictionary_size"]).to eq(4)
    end

    it "maintains separate suggestions per instance" do
      species_checker = SpellKit::Checker.new
      species_checker.load!(dictionary: species_dict)

      symbols_checker = SpellKit::Checker.new
      symbols_checker.load!(dictionary: symbols_dict)

      species_suggestions = species_checker.suggest("mose", 3)
      symbols_suggestions = symbols_checker.suggest("brca", 3)

      expect(species_suggestions.map { |s| s["term"] }).to include("mouse")
      expect(symbols_suggestions.map { |s| s["term"] }).to include("brca1")
    end

    it "maintains separate edit distances per instance" do
      checker1 = SpellKit::Checker.new
      checker1.load!(dictionary: test_unigrams, edit_distance: 1)

      checker2 = SpellKit::Checker.new
      checker2.load!(dictionary: test_unigrams, edit_distance: 2)

      stats1 = checker1.stats
      stats2 = checker2.stats

      expect(stats1["edit_distance"]).to eq(1)
      expect(stats2["edit_distance"]).to eq(2)
    end
  end

  describe "configure block" do
    it "creates a configured instance" do
      checker = SpellKit.configure do |config|
        config.dictionary = test_unigrams
        config.edit_distance = 2
        config.frequency_threshold = 5.0
      end

      stats = checker.stats
      expect(stats["loaded"]).to be true
      expect(stats["dictionary_size"]).to eq(20)
      expect(stats["edit_distance"]).to eq(2)
    end

    it "becomes the default instance" do
      original_default = SpellKit.default
      original_stats = original_default.stats

      SpellKit.configure do |config|
        config.dictionary = species_dict
      end

      new_stats = SpellKit.stats
      expect(new_stats["dictionary_size"]).to eq(5)
      expect(new_stats["dictionary_size"]).not_to eq(original_stats["dictionary_size"])
    end
  end

  describe "thread safety" do
    it "allows concurrent access to different instances" do
      checker1 = SpellKit::Checker.new
      checker1.load!(dictionary: test_unigrams)

      checker2 = SpellKit::Checker.new
      checker2.load!(dictionary: species_dict)

      threads = []
      results = []

      threads << Thread.new do
        100.times do
          results << checker1.suggest("helo", 1).first["term"]
        end
      end

      threads << Thread.new do
        100.times do
          results << checker2.suggest("mose", 1).first["term"]
        end
      end

      threads.each(&:join)

      expect(results).to include("hello", "mouse")
      expect(results.count).to eq(200)
    end
  end
end