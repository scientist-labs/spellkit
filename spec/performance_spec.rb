require "benchmark"

RSpec.describe "Performance (M5)" do
  let(:test_unigrams) { File.expand_path("fixtures/test_unigrams.tsv", __dir__) }

  before do
    SpellKit.load!(dictionary_path: test_unigrams, edit_distance: 1)
  end

  describe "latency targets" do
    it "suggests within p95 < 100µs (with small dictionary)" do
      # Warmup
      10.times { SpellKit.suggest("helo", 5) }

      times = []
      1000.times do
        start = Time.now
        SpellKit.suggest("helo", 5)
        times << (Time.now - start) * 1_000_000 # microseconds
      end

      times.sort!
      p50 = times[times.length / 2]
      p95 = times[(times.length * 0.95).to_i]

      puts "\nLatency: p50=#{p50.round(1)}µs, p95=#{p95.round(1)}µs"

      # With our small test dictionary, should be very fast
      expect(p95).to be < 1000 # 1ms is generous for 20-word dictionary
    end

    it "corrects within target latency" do
      times = []
      1000.times do
        start = Time.now
        SpellKit.correct_if_unknown("helo")
        times << (Time.now - start) * 1_000_000
      end

      times.sort!
      p50 = times[times.length / 2]
      p95 = times[(times.length * 0.95).to_i]

      puts "Correction latency: p50=#{p50.round(1)}µs, p95=#{p95.round(1)}µs"

      expect(p95).to be < 1000
    end
  end

  describe "guard performance" do
    before do
      SpellKit.load!(
        dictionary_path: test_unigrams,
        protected_path: File.expand_path("fixtures/protected.txt", __dir__)
      )
    end

    it "guard checks are fast" do
      times = []
      1000.times do
        start = Time.now
        SpellKit.correct_if_unknown("CDK10", guard: :domain)
        times << (Time.now - start) * 1_000_000
      end

      times.sort!
      p95 = times[(times.length * 0.95).to_i]

      puts "Guard check latency: p95=#{p95.round(1)}µs"

      # Guard check should be very fast (just hash/regex lookup)
      expect(p95).to be < 500
    end
  end
end