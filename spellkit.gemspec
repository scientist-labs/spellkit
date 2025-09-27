# frozen_string_literal: true

require_relative "lib/spellkit/version"

Gem::Specification.new do |spec|
  spec.name = "spellkit"
  spec.version = SpellKit::VERSION
  spec.authors = ["Chris Petersen"]
  spec.email = ["chris@petersen.io"]

  spec.summary = "Fast, safe typo correction for search-term extraction"
  spec.description = "A Ruby gem that provides fast typo correction using SymSpell algorithm, with domain-specific term protection"
  spec.homepage = "https://github.com/scientist-labs/spellkit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

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
  spec.extensions = ["ext/spellkit/extconf.rb"]

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
