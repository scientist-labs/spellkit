require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/extensiontask"

RSpec::Core::RakeTask.new(:spec)

Rake::ExtensionTask.new("spellkit") do |ext|
  ext.lib_dir = "lib/spellkit"
  ext.ext_dir = "ext/spellkit"
  ext.source_pattern = "*.{rs,toml}"
end

task default: [:compile, :spec]
