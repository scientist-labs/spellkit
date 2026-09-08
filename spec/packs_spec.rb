# frozen_string_literal: true

RSpec.describe SpellKit::Packs do
  let(:dictionary) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }
  let(:protected_terms) { File.expand_path("fixtures/protected.txt", __dir__) }

  before { described_class.reset! }
  after {
    described_class.reset!
    SpellKit.default = nil
  }

  def register(name = :demo, **overrides)
    described_class.register(name, dictionary: dictionary, **overrides)
  end

  describe "registration" do
    it "records a pack a data gem announces" do
      register

      expect(described_class.names).to eq([:demo])
      expect(described_class.registered?(:demo)).to be true
    end

    it "ships no packs of its own, so SpellKit knows the name of none" do
      # The "SpellKit doesn't bundle dictionaries" promise, as a test.
      expect(described_class.names).to be_empty
    end

    it "treats symbol, string and dashed spellings as one pack" do
      register(:general_medical)

      expect(described_class.registered?("general-medical")).to be true
      expect(described_class.registered?("General_Medical")).to be true
    end

    it "rejects a dictionary file that did not survive packaging" do
      # Checked at require time, while the stack still points at the offending gem,
      # rather than surfacing during someone's first search.
      expect { register(dictionary: "/nonexistent/dictionary.tsv") }
        .to raise_error(SpellKit::FileNotFoundError, /does not exist/)
    end

    it "rejects a missing protected-terms file too" do
      expect { register(protected_path: "/nonexistent/protected.txt") }
        .to raise_error(SpellKit::FileNotFoundError, /protected-terms file/)
    end
  end

  describe "pack-supplied tuning" do
    it "carries the defaults measured against that pack's own data" do
      register(defaults: {edit_distance: 2, frequency_threshold: 5.0})

      options = described_class.fetch(:demo).load_options

      expect(options[:edit_distance]).to eq(2)
      expect(options[:frequency_threshold]).to eq(5.0)
    end

    it "lets a caller override them" do
      register(defaults: {edit_distance: 2})

      expect(described_class.fetch(:demo).load_options(edit_distance: 1)[:edit_distance]).to eq(1)
    end

    it "accepts string keys from a data gem and hands load! symbols" do
      register(defaults: {"edit_distance" => 2})

      expect(described_class.fetch(:demo).load_options).to include(edit_distance: 2)
    end
  end

  describe "unknown packs" do
    it "points at the Gemfile when nothing is registered" do
      expect { described_class.fetch(:general_medical) }
        .to raise_error(SpellKit::UnknownPackError, /add one to your Gemfile/)
    end

    it "lists what IS registered when something is" do
      register(:demo)

      expect { described_class.fetch(:finance) }
        .to raise_error(SpellKit::UnknownPackError, /Registered: \[:demo\]/)
    end
  end

  describe "SpellKit.enable_dictionary" do
    it "loads a registered pack into the default checker" do
      register(:demo, protected_path: protected_terms)

      SpellKit.enable_dictionary(:demo)

      expect(SpellKit.dictionary_loaded?).to be true
      expect(SpellKit.dictionary_pack.name).to eq("demo")
      expect(SpellKit.correct?("hello")).to be true
    end

    it "still accepts raw files, with no pack involved" do
      SpellKit.enable_dictionary(dictionary: dictionary)

      expect(SpellKit.dictionary_pack).to be_nil
      expect(SpellKit.correct?("hello")).to be true
    end

    it "asks for a pack or a dictionary when given neither" do
      expect { SpellKit.enable_dictionary }
        .to raise_error(SpellKit::InvalidArgumentError, /registered pack name or a dictionary/)
    end
  end
end
