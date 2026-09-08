# frozen_string_literal: true

RSpec.describe SpellKit::LazyChecker do
  let(:dictionary) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }

  before do
    SpellKit::Packs.reset!
    SpellKit::Packs.register(:demo, dictionary: dictionary, defaults: {edit_distance: 1})
  end

  after {
    SpellKit::Packs.reset!
    SpellKit.default = nil
  }

  describe "deferral" do
    it "registers without building an index" do
      SpellKit.enable_dictionary(:demo, lazy: true)

      expect(SpellKit.dictionary_loaded?).to be false
    end

    it "fails at boot on an unregistered pack, not on first search" do
      expect { SpellKit.enable_dictionary(:nope, lazy: true) }
        .to raise_error(SpellKit::UnknownPackError)
    end
  end

  describe "what triggers the load" do
    before { SpellKit.enable_dictionary(:demo, lazy: true) }

    it "loads on a real lookup" do
      expect(SpellKit.correct("helllo")).to eq("hello")
      expect(SpellKit.dictionary_loaded?).to be true
    end

    it "does NOT load on stats" do
      # A liveness probe must not be able to build a multi-gigabyte index in the very
      # process lazy loading exists to protect.
      expect(SpellKit.stats).to include("deferred" => true, "loaded" => false)
      expect(SpellKit.dictionary_loaded?).to be false
    end

    it "does NOT load on healthcheck" do
      expect(SpellKit.healthcheck).to include("deferred" => true)
      expect(SpellKit.dictionary_loaded?).to be false
    end

    it "reports real stats after loading" do
      SpellKit.correct("helllo")

      expect(SpellKit.stats["loaded"]).to be true
    end
  end

  describe "explicit warm-up" do
    it "loads on demand, for a web-server boot hook" do
      SpellKit.enable_dictionary(:demo, lazy: true)

      SpellKit.load_dictionary!

      expect(SpellKit.dictionary_loaded?).to be true
    end

    it "is a no-op when the checker was loaded eagerly" do
      SpellKit.enable_dictionary(:demo)

      expect { SpellKit.load_dictionary! }.not_to raise_error
      expect(SpellKit.dictionary_loaded?).to be true
    end
  end

  describe "thread safety" do
    it "builds the index at most once under concurrent first use" do
      # Without the mutex two simultaneous first requests each build an index. Count the
      # builds rather than trusting the lock by inspection.
      # Count actual index builds rather than a helper call: load! IS the expensive thing,
      # so counting it cannot drift if the resolution path is refactored again.
      builds = 0
      counter = Mutex.new
      allow_any_instance_of(SpellKit::Checker).to receive(:load!).and_wrap_original do |original, *args, **kwargs|
        counter.synchronize { builds += 1 }
        original.call(*args, **kwargs)
      end

      SpellKit.enable_dictionary(:demo, lazy: true)
      8.times.map { Thread.new { SpellKit.correct("helllo") } }.each(&:join)

      expect(builds).to eq(1)
    end
  end

  describe "backwards compatibility" do
    it "loads eagerly by default, so existing callers are unaffected" do
      SpellKit.enable_dictionary(:demo)

      expect(SpellKit.dictionary_loaded?).to be true
    end

    it "reports not-loaded when nothing is configured" do
      SpellKit.default = nil

      expect(SpellKit.dictionary_loaded?).to be false
    end
  end

  describe "independent lazy checkers" do
    it "defers without touching the default checker" do
      checker = SpellKit.dictionary_checker(:demo, lazy: true)

      expect(checker.loaded?).to be false
      expect(checker.correct("helllo")).to eq("hello")
      expect(checker.loaded?).to be true
    end
  end
end
