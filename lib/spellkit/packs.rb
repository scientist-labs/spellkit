# frozen_string_literal: true

module SpellKit
  # A dictionary pack that some other gem has registered.
  #
  # SpellKit ships NO packs and knows the name of none. It provides the mechanism; a
  # separate data gem (spellkit-general-medical, say) requires itself, calls
  # SpellKit::Packs.register, and supplies both the files and the tuning that was measured
  # against them. That keeps the "SpellKit doesn't bundle dictionaries" promise in the
  # README literally true while still letting `SpellKit.enable_dictionary(:some_pack)`
  # work, and it means a pack can ship a new version - new terms, new tuning - without
  # SpellKit releasing anything at all.
  Pack = Struct.new(:name, :dictionary, :protected_path, :defaults, :summary, keyword_init: true) do
    # The keyword arguments to hand to load!, with caller overrides applied last.
    def load_options(**overrides)
      options = {dictionary: dictionary.to_s}
      options[:protected_path] = protected_path.to_s if protected_path
      defaults.merge(options).merge(overrides)
    end
  end

  # The registry of packs some installed gem has announced.
  module Packs
    class << self
      def registry
        @registry ||= {}
      end

      # Called by a data gem when it loads.
      #
      #   SpellKit::Packs.register(:general_medical,
      #     dictionary: "#{__dir__}/../data/dictionary.tsv",
      #     protected_path: "#{__dir__}/../data/protected.txt",
      #     defaults: {edit_distance: 2, frequency_threshold: 1.0})
      #
      # `defaults` is how a pack ships the tuning that was measured against ITS data,
      # rather than leaving every consumer to rediscover it.
      def register(name, dictionary:, protected_path: nil, defaults: {}, summary: nil)
        key = normalize(name)

        # Checked here, at require time, rather than on first use: a data gem whose files
        # did not survive packaging is broken, and saying so while the stack still points
        # at that gem beats an inexplicable failure during someone's first search. This is
        # a stat, so it costs nothing and does not defeat lazy loading, which exists to
        # defer the index BUILD.
        unless File.exist?(dictionary.to_s)
          raise FileNotFoundError,
            "Pack #{key.inspect} registered a dictionary that does not exist: #{dictionary}"
        end

        if protected_path && !File.exist?(protected_path.to_s)
          raise FileNotFoundError,
            "Pack #{key.inspect} registered a protected-terms file that does not exist: #{protected_path}"
        end

        registry[key] = Pack.new(
          name: key, dictionary: dictionary, protected_path: protected_path,
          defaults: symbolize(defaults), summary: summary
        )
      end

      def registered?(name)
        registry.key?(normalize(name))
      end

      # [:general_medical, ...]
      def names
        registry.keys.map(&:to_sym)
      end

      def fetch(name)
        registry.fetch(normalize(name)) do
          raise UnknownPackError, unknown_message(name)
        end
      end

      # Test hook.
      def reset!
        @registry = {}
      end

      # :general_medical, "general_medical" and "general-medical" all address one pack.
      def normalize(name)
        name.to_s.strip.downcase.tr("-", "_")
      end

      private

      def unknown_message(name)
        if registry.empty?
          "No dictionary packs are registered. A pack lives in its own gem - add one to " \
          "your Gemfile (e.g. gem \"spellkit-general-medical\") and it registers itself " \
          "when it loads. To use your own files instead, pass them directly: " \
          "SpellKit.enable_dictionary(dictionary: \"path/to.tsv\")."
        else
          "Unknown dictionary pack #{name.inspect}. Registered: #{names.inspect}. A pack " \
          "registers itself when its gem loads, so a missing one usually means the gem is " \
          "not in your Gemfile."
        end
      end

      def symbolize(hash)
        (hash || {}).each_with_object({}) { |(key, value), acc| acc[key.to_sym] = value }
      end
    end
  end
end
