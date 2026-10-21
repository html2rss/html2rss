# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Log do # rubocop:disable RSpec/SpecFilePathFormat -- ratchet spans feed-path tree
  # Production feed logs must be JSON hashes with event_name so html2rss-web
  # promotes columnar fields. mcp/cli/doctor/test/capture stay free-form.
  it 'has no Log.info/Log.warn string call sites under the feed path' do # rubocop:disable RSpec/ExampleLength -- tree scan
    excluded = %r{(?:/mcp/|/cli/|/doctor/|/test/|capture\.rb)}
    offenders = Dir[File.expand_path('../../../lib/html2rss/**/*.rb', __dir__)].flat_map do |path|
      next [] if path.match?(excluded)

      File.readlines(path).each_with_index.filter_map do |line, index|
        next unless line.match?(/\b(?:Html2rss::)?Log\.(?:info|warn)\(\s*(?:['"#%]|<<-?)/)

        "#{path}:#{index + 1}:#{line.strip}"
      end
    end

    expect(offenders).to eq([])
  end
end
