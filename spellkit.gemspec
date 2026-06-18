# frozen_string_literal: true

require_relative "lib/spellkit/version"

Gem::Specification.new do |spec|
  spec.name = "spellkit"
  spec.version = SpellKit::VERSION
  spec.authors = ["Chris Petersen"]
  spec.email = ["chris@petersen.io"]

  spec.summary = "Fast, safe typo correction for search-term extraction"
  spec.description = "A Ruby gem with a native Rust implementation of the SymSpell algorithm for fast typo correction with domain-specific term protection"
  spec.homepage = "https://github.com/scientist-labs/spellkit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Indicate that Rust toolchain is required to build this gem
  spec.requirements = ["Rust >= 1.85"]

  spec.files = Dir.glob(%w[
    lib/**/*.rb
    ext/**/*.{rb,rs,toml,lock}
    src/**/*.rs
    Cargo.toml
    Cargo.lock
    LICENSE
    README.md
  ])
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Precompiled platform gems (e.g. arm64-darwin, built natively on a macOS runner)
  # carry one compiled extension per Ruby ABI under lib/spellkit/<major.minor>/ and must
  # NOT declare extensions, or RubyGems would try to recompile from Rust source on
  # install — defeating the precompiled gem. The linux platform gems are assembled by
  # rake-compiler/rb_sys (via oxidize-rb cross-gem), which clears extensions itself; this
  # env gate covers the manually-assembled darwin fat gem. Unset => normal source gem.
  if (platform_gem = ENV["RUST_GEM_PLATFORM"])
    spec.platform = platform_gem
    spec.extensions = []
    spec.files += Dir["lib/spellkit/*/spellkit.bundle"] + Dir["lib/spellkit/*/spellkit.so"]
  else
    spec.extensions = ["ext/spellkit/extconf.rb"]
  end

  spec.add_dependency "rb_sys", "~> 0.9"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.2"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "standard", "~> 1.3"
  spec.add_development_dependency "irb"
  spec.add_development_dependency "benchmark-ips"
  spec.add_development_dependency "ffi-aspell"
end
