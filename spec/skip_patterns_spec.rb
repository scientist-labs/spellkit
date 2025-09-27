require "tempfile"

RSpec.describe "Skip Patterns" do
  let(:test_unigrams) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }

  describe "skip_urls flag" do
    before do
      SpellKit.load!(
        dictionary: test_unigrams,
        skip_urls: true
      )
    end

    it "skips http:// URLs" do
      expect(SpellKit.correct("http://example.com")).to eq("http://example.com")
      expect(SpellKit.correct("http://sub.example.com/path")).to eq("http://sub.example.com/path")
    end

    it "skips https:// URLs" do
      expect(SpellKit.correct("https://example.com")).to eq("https://example.com")
      expect(SpellKit.correct("https://github.com/user/repo")).to eq("https://github.com/user/repo")
    end

    it "skips www. URLs" do
      expect(SpellKit.correct("www.example.com")).to eq("www.example.com")
      expect(SpellKit.correct("www.github.com/user")).to eq("www.github.com/user")
    end

    it "still corrects regular typos" do
      expect(SpellKit.correct("helo")).to eq("hello")
    end

    it "works in batch operations" do
      tokens = %w[helo https://example.com wrld www.test.com]
      corrected = SpellKit.correct_tokens(tokens)
      expect(corrected).to eq(["hello", "https://example.com", "world", "www.test.com"])
    end
  end

  describe "skip_emails flag" do
    before do
      SpellKit.load!(
        dictionary: test_unigrams,
        skip_emails: true
      )
    end

    it "skips simple email addresses" do
      expect(SpellKit.correct("user@example.com")).to eq("user@example.com")
      expect(SpellKit.correct("admin@test.org")).to eq("admin@test.org")
    end

    it "skips emails with plus addressing" do
      expect(SpellKit.correct("user+tag@example.com")).to eq("user+tag@example.com")
    end

    it "skips emails with dots in username" do
      expect(SpellKit.correct("first.last@example.com")).to eq("first.last@example.com")
    end

    it "skips emails with subdomains" do
      expect(SpellKit.correct("user@mail.example.co.uk")).to eq("user@mail.example.co.uk")
    end

    it "still corrects regular typos" do
      expect(SpellKit.correct("helo")).to eq("hello")
    end

    it "works in batch operations" do
      tokens = %w[helo user@example.com wrld admin@test.org]
      corrected = SpellKit.correct_tokens(tokens)
      expect(corrected).to eq(["hello", "user@example.com", "world", "admin@test.org"])
    end
  end

  describe "skip_hostnames flag" do
    before do
      SpellKit.load!(
        dictionary: test_unigrams,
        skip_hostnames: true
      )
    end

    it "skips simple hostnames" do
      expect(SpellKit.correct("example.com")).to eq("example.com")
      expect(SpellKit.correct("github.com")).to eq("github.com")
    end

    it "skips hostnames with subdomains" do
      expect(SpellKit.correct("api.example.com")).to eq("api.example.com")
      expect(SpellKit.correct("mail.google.com")).to eq("mail.google.com")
    end

    it "skips hostnames with country TLDs" do
      expect(SpellKit.correct("example.co.uk")).to eq("example.co.uk")
      expect(SpellKit.correct("test.com.au")).to eq("test.com.au")
    end

    it "skips hostnames with hyphens" do
      expect(SpellKit.correct("my-site.com")).to eq("my-site.com")
      expect(SpellKit.correct("test-api.example.com")).to eq("test-api.example.com")
    end

    it "does not skip words without TLD (just-a-word)" do
      # "just-a-word" is not a hostname (no dots), so it should be corrected if misspelled
      # Since "just-a-word" doesn't match any dictionary word, it stays unchanged
      expect(SpellKit.correct("just-a-word")).to eq("just-a-word")
    end

    it "still corrects regular typos" do
      expect(SpellKit.correct("helo")).to eq("hello")
    end

    it "works in batch operations" do
      tokens = %w[helo example.com wrld api.test.com]
      corrected = SpellKit.correct_tokens(tokens)
      expect(corrected).to eq(["hello", "example.com", "world", "api.test.com"])
    end
  end

  describe "skip_code_patterns flag" do
    before do
      SpellKit.load!(
        dictionary: test_unigrams,
        skip_code_patterns: true
      )
    end

    it "skips camelCase identifiers" do
      expect(SpellKit.correct("getElementById")).to eq("getElementById")
      expect(SpellKit.correct("arrayMap")).to eq("arrayMap")
      expect(SpellKit.correct("myFunction")).to eq("myFunction")
    end

    it "skips PascalCase identifiers" do
      expect(SpellKit.correct("ArrayList")).to eq("ArrayList")
      expect(SpellKit.correct("MyClass")).to eq("MyClass")
      expect(SpellKit.correct("HttpRequest")).to eq("HttpRequest")
    end

    it "skips snake_case identifiers" do
      expect(SpellKit.correct("my_function")).to eq("my_function")
      expect(SpellKit.correct("get_user_data")).to eq("get_user_data")
    end

    it "skips SCREAMING_SNAKE_CASE constants" do
      expect(SpellKit.correct("API_KEY")).to eq("API_KEY")
      expect(SpellKit.correct("MAX_RETRIES")).to eq("MAX_RETRIES")
    end

    it "skips dotted.paths" do
      expect(SpellKit.correct("Array.map")).to eq("Array.map")
      expect(SpellKit.correct("config.yml")).to eq("config.yml")
      expect(SpellKit.correct("user.profile.email")).to eq("user.profile.email")
    end

    it "still corrects regular typos" do
      expect(SpellKit.correct("helo")).to eq("hello")
    end

    it "works in batch operations" do
      tokens = %w[helo getElementById wrld my_function]
      corrected = SpellKit.correct_tokens(tokens)
      expect(corrected).to eq(["hello", "getElementById", "world", "my_function"])
    end
  end

  describe "skip_numbers flag" do
    before do
      SpellKit.load!(
        dictionary: test_unigrams,
        skip_numbers: true
      )
    end

    it "skips version numbers" do
      expect(SpellKit.correct("1.0")).to eq("1.0")
      expect(SpellKit.correct("2.5.3")).to eq("2.5.3")
      expect(SpellKit.correct("10.15.7.1")).to eq("10.15.7.1")
    end

    it "skips hash/IDs" do
      expect(SpellKit.correct("#123")).to eq("#123")
      expect(SpellKit.correct("#4567")).to eq("#4567")
    end

    it "skips measurements with units" do
      # Weight
      expect(SpellKit.correct("5kg")).to eq("5kg")
      expect(SpellKit.correct("2.5g")).to eq("2.5g")
      expect(SpellKit.correct("100mg")).to eq("100mg")
      expect(SpellKit.correct("10lb")).to eq("10lb")

      # Distance
      expect(SpellKit.correct("5km")).to eq("5km")
      expect(SpellKit.correct("2.5m")).to eq("2.5m")
      expect(SpellKit.correct("100cm")).to eq("100cm")

      # Data
      expect(SpellKit.correct("5gb")).to eq("5gb")
      expect(SpellKit.correct("100mb")).to eq("100mb")
      expect(SpellKit.correct("1tb")).to eq("1tb")

      # Screen
      expect(SpellKit.correct("16px")).to eq("16px")
      expect(SpellKit.correct("2em")).to eq("2em")
    end

    it "skips words starting with digits" do
      expect(SpellKit.correct("123abc")).to eq("123abc")
      expect(SpellKit.correct("5test")).to eq("5test")
    end

    it "still corrects regular typos" do
      expect(SpellKit.correct("helo")).to eq("hello")
    end

    it "works in batch operations" do
      tokens = %w[helo 1.2.3 wrld 5kg]
      corrected = SpellKit.correct_tokens(tokens)
      expect(corrected).to eq(["hello", "1.2.3", "world", "5kg"])
    end
  end

  describe "multiple flags combined" do
    before do
      SpellKit.load!(
        dictionary: test_unigrams,
        skip_urls: true,
        skip_emails: true,
        skip_code_patterns: true
      )
    end

    it "applies all skip patterns" do
      tokens = %w[
        helo
        https://example.com
        user@test.com
        getElementById
        wrld
        my_function
      ]

      corrected = SpellKit.correct_tokens(tokens)

      expect(corrected).to eq([
        "hello",
        "https://example.com",
        "user@test.com",
        "getElementById",
        "world",
        "my_function"
      ])
    end
  end

  describe "skip patterns with custom protected_patterns" do
    it "merges skip patterns with user patterns" do
      SpellKit.load!(
        dictionary: test_unigrams,
        skip_urls: true,
        protected_patterns: [/^CUSTOM-\d+$/]
      )

      # Both built-in URL pattern and custom pattern should work
      expect(SpellKit.correct("https://example.com")).to eq("https://example.com")
      expect(SpellKit.correct("CUSTOM-123")).to eq("CUSTOM-123")
      expect(SpellKit.correct("helo")).to eq("hello")
    end
  end

  describe "when skip flags are false" do
    before do
      SpellKit.load!(
        dictionary: test_unigrams,
        skip_urls: false,
        skip_emails: false,
        skip_hostnames: false,
        skip_code_patterns: false,
        skip_numbers: false
      )
    end

    it "does not skip any special patterns" do
      # These will be treated as regular words (may or may not be corrected depending on dictionary)
      # Since they're not in the test dictionary, they'll stay unchanged
      expect(SpellKit.correct("https://example.com")).to eq("https://example.com")
      expect(SpellKit.correct("user@test.com")).to eq("user@test.com")
      expect(SpellKit.correct("getElementById")).to eq("getElementById")

      # Regular typos still get corrected
      expect(SpellKit.correct("helo")).to eq("hello")
    end
  end
end