require "webmock/rspec"

RSpec.describe "Dictionary Loading" do
  describe "from URL" do
    it "downloads and caches dictionary from URL" do
      # Mock HTTP response with a simple dictionary
      stub_request(:get, "https://example.com/dict.txt")
        .to_return(status: 200, body: "hello\t10000\nworld\t5000\n")

      SpellKit.load!(dictionary: "https://example.com/dict.txt")

      # Verify it loaded correctly
      suggestions = SpellKit.suggest("helo", 1)
      expect(suggestions.first["term"]).to eq("hello")
    end

    it "uses cached dictionary on subsequent loads" do
      # Mock HTTP response - should only be called once
      stub_request(:get, "https://example.com/cached.txt")
        .to_return(status: 200, body: "test\t1000\n")
        .times(1)

      # First load - downloads
      SpellKit.load!(dictionary: "https://example.com/cached.txt")

      # Second load - uses cache (won't trigger HTTP request again)
      expect {
        SpellKit.load!(dictionary: "https://example.com/cached.txt")
      }.not_to raise_error
    end

    it "raises error on download failure" do
      stub_request(:get, "https://example.com/missing.txt")
        .to_return(status: 404)

      expect {
        SpellKit.load!(dictionary: "https://example.com/missing.txt")
      }.to raise_error(SpellKit::DownloadError, /Failed to download dictionary/)
    end

    it "raises error on invalid URL" do
      expect {
        SpellKit.load!(dictionary: "not-a-valid-url")
      }.to raise_error(SpellKit::FileNotFoundError)
    end
  end

  describe "from file path" do
    let(:test_dict) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }

    it "loads dictionary from file path" do
      SpellKit.load!(dictionary: test_dict)

      suggestions = SpellKit.suggest("helo", 1)
      expect(suggestions.first["term"]).to eq("hello")
    end

    it "raises error if file doesn't exist" do
      expect {
        SpellKit.load!(dictionary: "nonexistent.tsv")
      }.to raise_error(SpellKit::FileNotFoundError)
    end
  end

  describe "DEFAULT_DICTIONARY_URL constant" do
    it "is defined and is a valid URL" do
      expect(SpellKit::DEFAULT_DICTIONARY_URL).to match(%r{^https://})
    end
  end
end