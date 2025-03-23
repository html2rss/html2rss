# frozen_string_literal: true

require 'vcr'

if ENV['COVERAGE']
  require 'simplecov'

  SimpleCov.start do
    enable_coverage :branch

    add_filter '/spec/'

    minimum_coverage 95
    minimum_coverage_by_file 90

    add_group 'Config', 'lib/html2rss/config'
    add_group 'Request Service', 'lib/html2rss/request_service'
    add_group 'Auto Source', 'lib/html2rss/auto_source'
    add_group 'Selectors', 'lib/html2rss/selectors'
    add_group 'RSS Builder', 'lib/html2rss/rss_builder'
    add_group 'Html Extractor', 'lib/html2rss/html_extractor'
  end
end

require 'html2rss'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  VCR.configure do |vcr_config|
    vcr_config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
    vcr_config.hook_into :faraday
  end
end
