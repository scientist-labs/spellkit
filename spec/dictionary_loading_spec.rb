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
      }.to raise_error(SpellKit::DownloadError, /HTTP 404/)
    end

    it "raises error on invalid URL" do
      expect {
        SpellKit.load!(dictionary: "not-a-valid-url")
      }.to raise_error(SpellKit::FileNotFoundError)
    end

    it "follows redirects successfully" do
      # Mock a 302 redirect chain
      stub_request(:get, "https://example.com/redirect1")
        .to_return(status: 302, headers: {"Location" => "https://example.com/redirect2"})

      stub_request(:get, "https://example.com/redirect2")
        .to_return(status: 301, headers: {"Location" => "https://example.com/final"})

      stub_request(:get, "https://example.com/final")
        .to_return(status: 200, body: "test\t1000\n")

      SpellKit.load!(dictionary: "https://example.com/redirect1")
      suggestions = SpellKit.suggest("test", 1)
      expect(suggestions.first["term"]).to eq("test")
    end

    it "follows relative redirects" do
      # Mock a relative redirect
      stub_request(:get, "https://example.com/path/dict.txt")
        .to_return(status: 302, headers: {"Location" => "/final/dict.txt"})

      stub_request(:get, "https://example.com/final/dict.txt")
        .to_return(status: 200, body: "test\t1000\n")

      SpellKit.load!(dictionary: "https://example.com/path/dict.txt")
      suggestions = SpellKit.suggest("test", 1)
      expect(suggestions.first["term"]).to eq("test")
    end

    it "raises error on too many redirects" do
      # Mock infinite redirect loop
      stub_request(:get, "https://example.com/loop1")
        .to_return(status: 302, headers: {"Location" => "https://example.com/loop2"})

      stub_request(:get, "https://example.com/loop2")
        .to_return(status: 302, headers: {"Location" => "https://example.com/loop3"})

      stub_request(:get, "https://example.com/loop3")
        .to_return(status: 302, headers: {"Location" => "https://example.com/loop4"})

      stub_request(:get, "https://example.com/loop4")
        .to_return(status: 302, headers: {"Location" => "https://example.com/loop5"})

      stub_request(:get, "https://example.com/loop5")
        .to_return(status: 302, headers: {"Location" => "https://example.com/loop6"})

      stub_request(:get, "https://example.com/loop6")
        .to_return(status: 302, headers: {"Location" => "https://example.com/loop1"})

      expect {
        SpellKit.load!(dictionary: "https://example.com/loop1")
      }.to raise_error(SpellKit::DownloadError, /Too many redirects/)
    end

    it "raises error on redirect with missing Location header" do
      stub_request(:get, "https://example.com/bad-redirect")
        .to_return(status: 302, headers: {})

      expect {
        SpellKit.load!(dictionary: "https://example.com/bad-redirect")
      }.to raise_error(SpellKit::DownloadError, /Redirect missing Location header/)
    end

    it "raises error on connection timeout" do
      stub_request(:get, "https://example.com/slow.txt")
        .to_timeout

      expect {
        SpellKit.load!(dictionary: "https://example.com/slow.txt")
      }.to raise_error(SpellKit::DownloadError, /timed out/)
    end

    it "raises error on read timeout" do
      stub_request(:get, "https://example.com/slow-read.txt")
        .to_raise(Net::ReadTimeout.new("execution expired"))

      expect {
        SpellKit.load!(dictionary: "https://example.com/slow-read.txt")
      }.to raise_error(SpellKit::DownloadError, /timed out/)
    end

    it "raises error on network failure" do
      stub_request(:get, "https://example.com/network-error.txt")
        .to_raise(SocketError.new("getaddrinfo: Name or service not known"))

      expect {
        SpellKit.load!(dictionary: "https://example.com/network-error.txt")
      }.to raise_error(SpellKit::DownloadError, /Network error/)
    end

    it "raises error on HTTP server errors" do
      stub_request(:get, "https://example.com/server-error.txt")
        .to_return(status: 500, body: "Internal Server Error")

      expect {
        SpellKit.load!(dictionary: "https://example.com/server-error.txt")
      }.to raise_error(SpellKit::DownloadError, /HTTP 500/)
    end

    it "raises error on SSL verification failure" do
      stub_request(:get, "https://example.com/ssl-error.txt")
        .to_raise(OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=error"))

      expect {
        SpellKit.load!(dictionary: "https://example.com/ssl-error.txt")
      }.to raise_error(SpellKit::DownloadError, /SSL verification failed/)
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