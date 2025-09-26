RSpec.describe "Manifest support" do
  let(:test_unigrams) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }
  let(:manifest_file) { File.expand_path("fixtures/symspell.json", __dir__) }

  it "loads manifest version" do
    SpellKit.load!(
      dictionary: test_unigrams,
      manifest_path: manifest_file
    )

    stats = SpellKit.stats
    expect(stats["version"]).to eq("test-2025-01-01")
  end

  it "works without manifest" do
    SpellKit.load!(dictionary: test_unigrams)

    stats = SpellKit.stats
    expect(stats["version"]).to be_nil
  end
end