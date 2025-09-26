require_relative "spellkit/version"

begin
  require "spellkit/spellkit"
rescue LoadError
  require "spellkit.bundle"
end

module SpellKit
  class Error < StandardError; end

  class << self
    def load!(unigrams_path:, edit_distance: 1, **_options)
      load_dictionary(unigrams_path.to_s, edit_distance)
    end
  end
end
