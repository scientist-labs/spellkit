# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
end

require "spellkit"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # `require "webmock/rspec"` in dictionary_loading_spec.rb disables net connect for the
  # WHOLE suite, not just that file - so the two examples tagged :integration, whose entire
  # purpose is to prove DEFAULT_DICTIONARY_URL really resolves and loads, were blocked by
  # WebMock and failed on every Ruby. That is why every build run on this repo has been red.
  #
  # Let a tagged example reach the network, and restore the block afterwards so no other
  # example inherits it.
  config.around(:each, :integration) do |example|
    WebMock.allow_net_connect! if defined?(WebMock)
    example.run
    WebMock.disable_net_connect!(allow_localhost: true) if defined?(WebMock)
  end
end
