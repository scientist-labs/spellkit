require "bundler/gem_tasks"
require "rake/extensiontask"

# rspec is a dev-only dependency. The rb-sys-dock cross container installs the
# RUNTIME bundle only, so this require must not be allowed to break Rakefile load
# during the linux cross build.
begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  desc "spec (rspec unavailable here)"
  task(:spec) { abort "rspec is a dev dependency" }
end

Rake::ExtensionTask.new("spellkit") do |ext|
  ext.lib_dir = "lib/spellkit"
  ext.ext_dir = "ext/spellkit"
  ext.source_pattern = "*.{rs,toml}"
  # Precompiled cross-gem build (x86_64-linux + aarch64-linux via rb-sys-dock,
  # arm64-darwin natively on macOS) for the shared rust-gem-release matrix.
  ext.cross_compile = true
  ext.cross_platform = %w[x86_64-linux aarch64-linux arm64-darwin]
end

task default: [:compile, :spec]
